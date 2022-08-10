// SPDX-License-Identifier: MIT

pragma solidity =0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract VestingTokenSale is Ownable {
    uint public constant CLIFF_PERIOD = 365 days;
    uint public constant VESTING_PERIOD = 365 days;

    uint public totalSold;
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
        bool allReleased;
    }

    mapping(address => uint) private _pBalance;
    mapping(address => uint) private _rBalance;
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
     * @notice Purchase tokens
     * @param allowance the amount of usdc tokens to spend
     */
    function purchase(uint allowance) external onSale notPaused {
        uint tokenAmt = getTokenAmount(allowance);
        require(allowance > 0 && remainingTokens() >= tokenAmt, "INVALID_AMOUNT");
        if(presale)
            require(_whitelist[msg.sender], "NOT_WHITELISTED");

        _pBalance[msg.sender] += tokenAmt;

        if(_pLimit[msg.sender] != 0)
            require(_pLimit[msg.sender] > _pBalance[msg.sender], "EXCEEDS_PURCHASE_LIMIT");
        
        totalSold += tokenAmt;
        _allocations[msg.sender].push(Allocation({
            vestingStart: block.timestamp + CLIFF_PERIOD,
            amount: tokenAmt,
            released: 0,
            allReleased: false
        }));

        USDC.transferFrom(msg.sender, _vault, allowance);
        
        emit TokensPurchased(msg.sender, tokenAmt);

    }

    /**
     * @notice Release tokens that have already vested.
     */
    function release() external holderOnly {
        require(_allocations[msg.sender].length > 0, "NO_ALLOC");

        uint rTotal;

        for(uint i = 0; i < _allocations[msg.sender].length; i++) {
            Allocation storage allocation = _allocations[msg.sender][i];

            if(allocation.allReleased) 
                continue;

            uint releasable = _vestedAmount(i) - allocation.released;

            if(releasable == 0) 
                break;
            
            rTotal += releasable;

            allocation.released += releasable;
            allocation.amount -= releasable;
            
            if(allocation.amount == 0)
                allocation.allReleased = true;
        }
        
        if(rTotal == 0)
            revert("NO_TOKENS_VESTED");

        _rBalance[msg.sender] += rTotal;

        token.transfer(msg.sender, rTotal);

        emit TokenReleased(msg.sender, rTotal);

    }

    function getVestedAmount() external view returns (uint) {
        if(_allocations[msg.sender].length == 0) return 0;
        
        uint rTotal;

        for(uint i = 0; i < _allocations[msg.sender].length; i++) {
            if(_allocations[msg.sender][i].allReleased) continue;

            uint releasable = _vestedAmount(i) - _allocations[msg.sender][i].released;

            if(releasable == 0) 
                break;
            
            rTotal += releasable;
        }

        return rTotal;
    }

    /**
     * @notice Returns amount of tokens already released to the user
     */
    function releasedAmount(address holder) external view returns (uint) {
        return _rBalance[holder];
    }

    /**
     * @dev Calculates the amount of tokens that has already vested. Default implementation is a linear vesting curve.
     */
    function _vestedAmount(uint index) internal view virtual returns (uint) {
        return _vestingSchedule(_allocations[msg.sender][index].amount + _allocations[msg.sender][index].released, index);
    }

    /**
     * @dev Virtual implementation of the vesting formula. This returns the amount vested, as a function of time, for
     * an asset given its total historical allocation.
     */
    function _vestingSchedule(uint totalAllocation, uint index) internal view virtual returns (uint) {
        uint vStart = _allocations[msg.sender][index].vestingStart;
        uint timestamp = block.timestamp;
    
        if (timestamp < vStart) 
            return 0;

        return timestamp > vStart + VESTING_PERIOD 
        ? totalAllocation 
        : (totalAllocation * (timestamp - vStart)) / VESTING_PERIOD;
    }

    /**
     * @notice Returns amount of tokens available for sale
     */
    function remainingTokens() public view returns (uint) {
        return token.balanceOf(address(this)) - totalSold;
    }

    /**
     * @notice Returns amount of tokens that can be bought for input amount of usdc
     * @param allowance amount of usdc to be used for purchase
     */
    function getTokenAmount(uint allowance) public view returns (uint) {
        return allowance * rate;
    }

    /**
     * @notice Returns total amount of tokens purchased by the user
     * @param user address to retrieve purchase balance of
     */
    function getPurchasedAmount(address user) external view returns (uint) {
        return _pBalance[user];
    }
    
    /**
     * @notice Returns if sale is currently ongoing
     */
    function saleActive() public view returns (bool) {
        return saleStartTime < block.timestamp && block.timestamp < saleEndTime;
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
     * @notice Include users into whitelist along with their purchase limits
     * @param users list of addresses to whitelist
     * @param limits list of limits corresponding to each whitelisted user
     * NOTE: Length of both input lists must be equal. Pass 0 as limit if limit should not be imposed on a specific address
     */
    function whitelist(
        address[] calldata users,
        uint[] calldata limits
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
