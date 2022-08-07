// SPDX-License-Identifier: MIT

pragma solidity =0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TokenSale is Ownable {
    uint256 public constant CLIFF_PERIOD = 365 days;
    uint256 public constant VESTING_PERIOD = 365 days;
    uint256 public purchaseLimit;
    uint256 public rate;

    address private _vault;
    bool public presale = true; 
    bool public paused = false;
    
    IERC20 private constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48); // Ethereum mainnet address
    IERC20 public token; // Token to be sold
    
    mapping(address => uint256) private _pBalance;
    mapping(address => bool) private _whitelist;

    event TokensPurchased(address _holder, address _vestContract, uint256 _amount);
    
    modifier notPaused() {
        require(paused == false, "PAUSED");
        _;
    }

    /**
     * @param _token address of token contract
     * @param vault_ address to send usdc received from sales
     * @param _rate conversion rate from usdc to sale token
     */
    constructor(address _token, address vault_, uint256 _rate, uint256 vestingPeriod) {
        if(_token == address(0) || vault_ == address(0) || _rate == 0)
            revert("INVALID_ARGS");

        _vault = vault_;
        rate = _rate;
        token = IERC20(_token);
    }
    
    /**
     * @notice Purchase tokens and deploys a vesting contract
     * @param amount the amount of tokens to be purchased
     */
    function purchase(uint256 amount) external notPaused {
        require(amount > 0 && contractBalance() > amount , "INVALID_AMOUNT");
        address recipient = _msgSender();
        
        if(presale)
            require(_whitelist[recipient], "NOT_WHITELISTED");

        _pBalance[recipient] += amount;

        require(purchaseLimit > _pBalance[recipient], "EXCEEDING_PURCHASE_LIMIT");

        USDC.transferFrom(recipient, _vault, amount / rate);
        
        address vestContract = 

        token.transfer(vestContract, amount);

        emit TokensPurchased(recipient, amount);

    }

    /**
     * @notice Returns amount of tokens available for sale
     */
    function contractBalance() public view returns (uint256) {
        return token.balanceOf(address(this));
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
        for(uint256 i = 0; i < users.length; i++)
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
        for(uint256 i = 0; i < users.length; i++)
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
    function setPurchaseLimit(uint256 newPurchaseLimit) external onlyOwner {
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

}
