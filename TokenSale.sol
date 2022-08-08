// SPDX-License-Identifier: MIT

pragma solidity =0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TokenSale is Ownable {
    uint public constant CLIFF_PERIOD = 365 days;
    uint public constant VESTING_PERIOD = 365 days;

    uint public purchaseLimit;
    uint public totalPurchased;
    uint public rate;
    uint public saleStartTime;
    uint public saleEndTime;

    address private _vault;
    bool public presale = true; 
    bool public paused = false;
    
    IERC20 private constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48); // Ethereum mainnet address
    IERC20 public token; // Token to be sold
    
    struct Allocation {
        uint vestingStart;
        uint amount;
        uint released;
    }

    mapping(address => uint) private _pBalance;
    mapping(address => bool) private _whitelist;
    mapping(address => Allocation[]) private _allocations;

    event TokensPurchased(address _holder, uint _amount);

    
    modifier notPaused() {
        require(paused == false, "PAUSED");
        _;
    }

    modifier onSale() {
        require(saleActive(), "SALE_INACTIVE");
        _;
    }
    
    /**
     * @param _token address of token contract
     * @param vault_ address to send usdc received from sales
     * @param _rate conversion rate from usdc to sale token
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
        address recipient = _msgSender();
        
        if(presale)
            require(_whitelist[recipient], "NOT_WHITELISTED");

        _pBalance[recipient] += _amount;

        totalPurchased += _amount;

        require(purchaseLimit > _pBalance[recipient], "EXCEEDING_PURCHASE_LIMIT");

        USDC.transferFrom(recipient, _vault, _amount / rate);
        
        _allocations[recipient].push(Allocation({
            vestingStart: block.timestamp + CLIFF_PERIOD,
            amount: _amount,
            released: 0
        }));

        emit TokensPurchased(recipient, _amount);

    }

    /**
     * @dev Removes first allocation of caller
     */
    function _removeFront() internal {
        Allocation[] storage allocations = _allocations[_msgSender()];
        
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
    function claim() external {
        address claimant = _msgSender();
        require(_pBalance[claimant] > 0, "NOT_HOLDER");
        Allocation storage allocation = _allocations[claimant][0];
        uint releasable = vestedAmount(block.timestamp) - allocation.released;
        if(releasable == 0) revert("NO_TOKENS_TO_CLAIM");

        allocation.released += releasable;
        allocation.amount -= releasable;

        if(allocation.amount == 0)
            _removeFront();

        token.transfer(claimant, releasable);
    }

    /**
     * @dev Calculates the amount of tokens that has already vested. Default implementation is a linear vesting curve.
     */
    function vestedAmount(uint timestamp) public view virtual returns (uint) {
        return _vestingSchedule(_allocations[_msgSender()][0].amount + _allocations[_msgSender()][0].released, timestamp);
    }

    /**
     * @dev Virtual implementation of the vesting formula. This returns the amount vested, as a function of time, for
     * an asset given its total historical allocation.
     */
    function _vestingSchedule(uint totalAllocation, uint timestamp) internal view virtual returns (uint) {
        uint vStart = _allocations[_msgSender()][0].vestingStart;

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
     * @notice Returns usdc required to purchase input amount of tokens
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
     * @notice Check if an address is whitelisted
     * @param user address to verify
     */
    function whitelisted(address user) external view returns (bool) {
        return _whitelist[user];
    }

    /* ||___ONLY-OWNER___|| */
    
    /**
     * @notice Include users into whitelist
     * @param users list of addresses to whitelist
     */
    function whitelist(
        address[] 
        calldata 
        users) 
    external onlyOwner {
        for(uint i = 0; i < users.length; i++)
            _whitelist[users[i]] = true;
    }

    /**
     * @notice Remove users from whitelist
     * @param users list of addresses to remove from whitelist
     */
    function whitelistExclude(
        address[] 
        calldata 
        users) 
    external onlyOwner {
        for(uint i = 0; i < users.length; i++)
            _whitelist[users[i]] = false;
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
     * @notice Change purchase limit
     * @param newPurchaseLimit new maximum amount of tokens a user can purchase
     */
    function setPurchaseLimit(uint newPurchaseLimit) external onlyOwner {
        purchaseLimit = newPurchaseLimit;
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
     * @notice Transfers unpledged tokens to contract owner
     */
    function withdrawTokens() external onlyOwner {
        token.transfer(msg.sender, remainingTokens());
    }

}
