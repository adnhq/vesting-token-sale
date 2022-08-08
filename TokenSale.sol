// SPDX-License-Identifier: MIT

pragma solidity =0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract VestingTokenSale is Ownable {
    uint public constant CLIFF_PERIOD = 365 days;
    uint public constant VESTING_PERIOD = 365 days;

    uint public totalPurchased;
    uint public rate; // How many token units a buyer gets for one unit of usdc - excluding decimals.
    // Rate should be calculated using only 1 unit of usdc - like wei, NOT a whole usdc token (1 * 10**6)
    uint public saleStartTime;
    uint public saleEndTime;

    address private _vault; // Address which will receive the usdc from purchases
    bool public presale = true; 
    bool public paused = false;
    
    IERC20 private constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48); // Ethereum mainnet address
    // Replace usdc address if used on a different blockchain
    IERC20 public token; // Token to be sold
    
    struct Allocation {
        uint vestingStart;
        uint amount;
        uint released;
    }

    mapping(address => uint) private _pBalance;
    mapping(address => uint) private _pLimit;
    mapping(address => bool) private _whitelist;
    mapping(address => Allocation[]) private _allocations;

    event TokensPurchased(address holder, uint amount);
    event TokenReleased(address recipient, uint amount);

    
    modifier notPaused() {
        require(paused == false, "PAUSED");
        _;
    }

    modifier onSale() {
        require(saleActive(), "SALE_INACTIVE");
        _;
    }
    
    modifier holderOnly() {
        require(_pBalance[msg.sender] > 0, "NOT_HOLDER");
        require(_allocations[msg.sender].length > 0, "CLAIMED_FULL");
        _;
    }

    /**
     * @param _token address of token contract
     * @param vault_ address to send usdc received from sales
     * @param _rate token units a buyer gets for one unit of usdc excluding decimals
     * @param _saleStartTime sale start unix timestamp in seconds
     * @param _saleEndTime sale end unix timestamp in seconds
     */
    constructor(
        address _token, 
        address vault_, 
        uint _rate, 
        uint _saleStartTime,
        uint _saleEndTime
    ) {
        if(_token == address(0) || vault_ == address(0) || _rate == 0 ||
         _saleStartTime < block.timestamp || _saleStartTime > _saleEndTime)
            revert("INVALID_ARGS");

        _vault = vault_;
        rate = _rate;
        saleStartTime = _saleStartTime;
        saleEndTime = _saleEndTime;

        token = IERC20(_token);
    }
    
    /**
     * @notice Purchase tokens and deploys a vesting contract
     * @param _amount the amount of tokens to be purchased
     */
    function purchase(uint _amount) external onSale notPaused {
        require(_amount > 0 && remainingTokens() > _amount , "INVALID_AMOUNT");
        if(presale)
            require(_whitelist[msg.sender], "NOT_WHITELISTED");

        _pBalance[msg.sender] += _amount;

        if(_pLimit[msg.sender] != 0)
            require(_pLimit[msg.sender] > _pBalance[msg.sender], "EXCEEDS_PURCHASE_LIMIT");
        
        totalPurchased += _amount;
        _allocations[msg.sender].push(Allocation({
            vestingStart: block.timestamp + CLIFF_PERIOD,
            amount: _amount,
            released: 0
        }));

        USDC.transferFrom(msg.sender, _vault, _amount / rate);
        
        emit TokensPurchased(msg.sender, _amount);

    }

    /**
     * @dev Removes first allocation of caller.
     */
    function _popFirst() private {
        Allocation[] storage allocations = _allocations[msg.sender];
        
        if (allocations.length == 0) return;

        for (uint i = 0; i < allocations.length-1; i++){
            allocations[i] = allocations[i+1];
        }

        delete allocations[allocations.length-1];
        allocations.pop();
    }

    /**
     * @notice Claim tokens that have already vested.
     */
    function claim() external holderOnly {
        Allocation storage allocation = _allocations[msg.sender][0];
        uint releasable = vestedAmount(block.timestamp) - allocation.released;
        if(releasable == 0) revert("NO_TOKENS_TO_CLAIM");

        allocation.released += releasable;
        allocation.amount -= releasable;
        
        // Remove first allocation if fully distributed
        if(allocation.amount == 0)
            _popFirst();

        token.transfer(msg.sender, releasable);

        emit TokenReleased(msg.sender, releasable);
    }

    /**
     * @dev Calculates the amount of tokens that has already vested. Default implementation is a linear vesting curve.
     */
    function vestedAmount(uint timestamp) public view virtual returns (uint) {
        return _vestingSchedule(_allocations[msg.sender][0].amount + _allocations[msg.sender][0].released, timestamp);
    }

    /**
     * @dev Virtual implementation of the vesting formula. This returns the amount vested, as a function of time, for
     * an asset given its total historical allocation.
     */
    function _vestingSchedule(uint totalAllocation, uint timestamp) internal view virtual returns (uint) {
        uint vStart = _allocations[msg.sender][0].vestingStart;

        if (timestamp < vStart) {
            return 0;
        } else if (timestamp > vStart + VESTING_PERIOD) {
            return totalAllocation;
        } else {
            return (totalAllocation * (timestamp - vStart)) / VESTING_PERIOD;
        }
    }

    /**
     * @notice Returns amount of tokens available for sale
     */
    function remainingTokens() public view returns (uint) {
        return token.balanceOf(address(this)) - totalPurchased;
    }

    /**
     * @notice Returns amount of usdc required to purchase input amount of tokens
     * @param amount amount of tokens to purchase
     */
    function getCost(uint amount) public view returns (uint) {
        return amount / rate;
    }

    /**
     * @notice Returns if sale is currently ongoing
     */
    function saleActive() public view returns (bool) {
        return saleStartTime > block.timestamp && block.timestamp < saleEndTime;
    }

    /**
     * @notice Returns if an address is whitelisted
     * @param user address to verify
     */
    function whitelisted(address user) external view returns (bool) {
        return _whitelist[user];
    }

    /* ||___ONLY-OWNER___|| */
    
    /**
     * @notice Include users into whitelist along with their purchase limits
     * @param users list of addresses to whitelist
     * @param limits list of limits corresponding to each whitelisted user
     * NOTE: Length of both input lists must be equal. Pass 0 as limit if limit should not be imposed on a specific address
     */
    function whitelist(
        address[] calldata users,
        uint[] limits
    ) external onlyOwner {
        require(users.length == limits.length, "UNEQUAL_LISTS");
        for(uint i = 0; i < users.length; i++) {
            _whitelist[users[i]] = true;
            _pLimit[users[i]] = limits[i];
        }
    }

    /**
     * @notice Remove users from whitelist
     * @param users list of addresses to remove from whitelist
     */
    function whitelistExclude(
        address[] 
        calldata 
        users
    ) external onlyOwner {
        for(uint i = 0; i < users.length; i++)
            _whitelist[users[i]] = false;
    }
    
    /**
     * @notice Set purchase limit for a specific user
     * @param user address of the user to put limit on
     * @param limit maximum amount of tokens the user can buy
     */
    function setPurchaseLimit(address user, uint limit) external onlyOwner {
        _pLimit[user] = limit;
    }

    /**
     * @notice Change vault address
     * @param newVault address of new vault
     */
    function setVault(address newVault) external onlyOwner {
        require(newVault != address(0), "NON_ZERO_REQ");
        _vault = newVault;
    }

    /**
     * @notice Start public sale
     */
    function initPublicSale() external onlyOwner {
        presale = false;
    }

    /**
     * @notice Pause token purchase
     */
    function pause() external onlyOwner {
        paused = true;
    }

    /**
     * @notice Resume token purchase
     */
    function unpause() external onlyOwner {
        paused = false;
    }

    /**
     * @notice Change sale start time
     * @param _startTime unix timestamp of new sale start time in seconds
     * NOTE: Can only be called before sale has started
     */
    function setSaleStartTime(uint _startTime) external onlyOwner {
        require(block.timestamp < saleStartTime, "SALE_STARTED");
        saleStartTime = _startTime;
    }

    /**
     * @notice Change sale end time
     * @param _endTime unix timestamp of new sale end time in seconds
     * NOTE: Can only be called before sale has ended
     */
    function setSaleEndTime(uint _endTime) external onlyOwner {
        require(block.timestamp < saleEndTime, "SALE_ENDED");
        saleEndTime = _endTime;
    }

    /**
     * @notice Transfers unsold tokens to contract owner
     */
    function withdrawTokens() external onlyOwner {
        token.transfer(msg.sender, remainingTokens());
    }

}
