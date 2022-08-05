// SPDX-License-Identifier: MIT

pragma solidity =0.8.15;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TokenSale is Ownable {
    uint256 public purchaseLimit;
    uint256 public rate;

    uint64 public constant CLIFF = 365 days;
    address depositAddr;
    bool public presale = true; 
    bool public paused = false;
    
    IERC20 private constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48); // Ethereum mainnet
    IERC20 public token; // Token to be sold
    
    mapping(address => uint256) private _pBalance;
    mapping(address => bool) private _whitelist;

    event TokensPurchased(address _holder, uint256 _amount);
    event TokensVested();
    
    modifier notPaused() {
        require(paused == false, "PAUSED");
        _;
    }

    constructor(address _token, address _depositAddr, uint256 _rate) {
        token = IERC20(_token);
        depositAddr = _depositAddr;
        rate = _rate;
    }
    
    /**
     * @notice Purchase tokens
     * @param amount the amount of tokens to be purchased including decimals
     */
    function purchase(uint256 amount) external notPaused {
        require(amount <= contractBalance(), "INSUFFICIENT_TOKENS");
        address msgSender = _msgSender();
        _pBalance[msgSender] += amount;
        require(purchaseLimit > _pBalance[msgSender], "EXCEEDING_PURCHASE_LIMIT");

        if(presale)
            require(_whitelist[msgSender], "NOT_WHITELISTED");
        
        uint256 amountRp = ;

        USDC.transferFrom(msgSender, depositAddr, amountRp);

        emit TokensPurchased(msgSender, amount);

    }

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

    /* ||___ ONLY-OWNER ___|| */
    
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
    
    function setDepositAddress(uint256 newDepositAddr) external onlyOwner {
        require(newDepositAddr != address(0), "NON_ZERO_REQ");
        depositAddr = newDepositAddr;
    }

    function setPurchaseLimit(uint256 newPurchaseLimit) external onlyOwner {
        purchaseLimit = newPurchaseLimit;
    }

    function initPublicSale() external onlyOwner {
        presale = false;
    }

    function pause() external onlyOwner {
        paused = true;
    }

    function unpause() external onlyOwner {
        paused = false;
    }

}
