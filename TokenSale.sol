// SPDX-License-Identifier: MIT

pragma solidity =0.8.15;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TokenSale is Ownable {
    uint256 public purchaseLimit;
    uint256 public rate;
    uint256 public totalPurchase;
    
    IERC20 private constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48); // Ethereum mainnet
    IERC20 public token; // Token to be sold
    
    bool public presale = true; 
    bool public paused = false;

    mapping(address => uint) private _pBalance;
    mapping(address => bool) private _whitelist;

    event TokenPurchase(address user, uint256 amountPurchased);
    
    modifier notPaused() {
        require(paused == false, "PAUSED");
        _;
    }

    constructor(address _token) {
        token = IERC20(_token);
    }

    function purchase(uint256 amount) external notPaused {
        require(amount <= contractBalance(), "INSUFFICIENT_TOKENS");
        _pBalance[_msgSender()] += amount;
        require(purchaseLimit > _pBalance[_msgSender()], "EXCEEDING_PURCHASE_LIMIT");

        if(presale)
            require(_whitelist[_msgSender()], "NOT_WHITELISTED");

        totalPurchase += amount;
        
        uint256 amountRp = ;

        USDC.transferFrom(_msgSender(), owner(), amountRp);

        // Check against contract balance
    }

    function contractBalance() public view returns (uint256) {
        return token.balanceOf(address(this));
    }

    /* ||___ONLY-OWNER___|| */

    function whitelist(
        address[] 
        calldata 
        users) 
    external onlyOwner {
        for(uint16 i; i < users.length; i++)
            _whitelist[users[i]] = true;
    }

    function revokeWhitelist(
        address[] 
        calldata 
        users) 
    external onlyOwner {
        for(uint16 i; i < users.length; i++)
            _whitelist[users[i]] = false;
    }

    function setPurchaseLimit(uint256 _purchaseLimit) external onlyOwner {
        purchaseLimit = _purchaseLimit;
    }

    function enablePublicSale() external onlyOwner {
        presale = false;
    }

    function pause() external onlyOwner {
        paused = true;
    }

    function unpause() external onlyOwner {
        paused = false;
    }

}
