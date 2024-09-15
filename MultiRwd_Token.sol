// SPDX-License-Identifier: MIT

pragma solidity 0.8.27;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v5.1/contracts/token/ERC20/ERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v5.1/contracts/access/Ownable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v5.1/contracts/utils/ReentrancyGuard.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v5.1/contracts/token/ERC20/utils/SafeERC20.sol";

interface iFactory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface iRouter {
    function WETH() external pure returns (address);
    function factory() external pure returns (address);
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable;
}

interface iDistrib {
    function setShare(address shareholder_, uint256 amount_) external;
    function process(uint256 gas_) external;
}

/*
 * Multi Reward Token
 * Developed by Kevin Remer (Totenmacher)
 */
contract Multi_RWD_Token is ERC20, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bool public tradingActive;

    iRouter public tokenRouter;
    address public tokenPair;

    mapping(address => bool) public isFeeExempt;
    mapping(address => bool) public isFreezeExempt;
    mapping(address => bool) public isRwdExempt;
    mapping(address => bool) public isProcessExempt;

    uint256 public rwdFee = 2;
    uint256 public opsFee = 1;

    uint256 public totalTax = rwdFee + opsFee;

    iDistrib public rwdDistributor;
    address public opsReceiver;

    uint256 public distribGas = 500_000;
    
    bool public swapEnabled;
    uint256 public swapThreshold;
    uint256 public averageTX;

    event adminAction(string Action, address Address, uint256 Amount);
    event tokenAction(string actionTaken_, address actionAddress, uint256 actionValue_, bool actionResult_);

    constructor(address router_, address defaultReceiver_, uint256 totalSupply_) ERC20("Full Token Name","FTN") Ownable(msg.sender) {
        tokenRouter = iRouter(router_);

        opsReceiver = defaultReceiver_;

        uint256 totalSupply = totalSupply_ * (10 ** 18);

        tokenPair = iFactory(tokenRouter.factory()).createPair(address(this), tokenRouter.WETH());
        swapThreshold = totalSupply / 2000;

        isFeeExempt[msg.sender] = true;
        isFreezeExempt[msg.sender] = true;
        isRwdExempt[msg.sender] = true;
        isProcessExempt[msg.sender] = true;

        isFeeExempt[defaultReceiver_] = true;
        isFreezeExempt[defaultReceiver_] = true;
        isRwdExempt[defaultReceiver_] = true;
        isProcessExempt[defaultReceiver_] = true;

        isRwdExempt[tokenPair] = true;

        isFeeExempt[address(this)] = true;
        isRwdExempt[address(this)] = true;

        super._update(address(0), defaultReceiver_, totalSupply);
    }

    receive() external payable {}

    fallback() external payable {}

    /*
     * Admin functions
     */

    // Clear WETH from contract
    function harvestWETH() external onlyOwner nonReentrant {
        uint256 fullBalance = address(this).balance;
        (bool sendSuccess, ) = payable(owner()).call{value: fullBalance}("");

        if (sendSuccess) {
            emit adminAction("harvestWETH", address(0), fullBalance);
        } else {
            emit adminAction("harvestWETH", address(0), 0);
        }
    }

    // Remove full balance of given token
    function clearStuckToken(address token_) external onlyOwner nonReentrant {
        uint256 sendAmount = IERC20(token_).balanceOf(address(this));
        IERC20(token_).safeTransfer(owner(), sendAmount);

        emit adminAction("clearStuckToken", token_, sendAmount);
    }

    // Update the distributor address
    function setDistributor(address rwdDistributor_) external onlyOwner {
        rwdDistributor = iDistrib(rwdDistributor_);

        emit adminAction("setDistributor", rwdDistributor_, 0);
    }

    // Update the ops reward receiver address
    function setOpsReceiver(address opsReceiver_) external onlyOwner {
        opsReceiver = opsReceiver_;

        emit adminAction("setOpsReceiver", opsReceiver_, 0);
    }

    // Set token active status
    function setTradingActive(bool tradingActive_) external onlyOwner {
        require(tradingActive != tradingActive_, "Status already set");
        tradingActive = tradingActive_;

        emit adminAction("setTradingActive", address(0), tradingActive_ ? 1 : 0);
    }

    // Add to fee exempt - Does not pay taxes on buys and sells
    function setFeeExempt(address wallet_, bool isFeeExempt_) external onlyOwner {
        require(wallet_ != address(0), "Cannot exempt 0 address");
        isFeeExempt[wallet_] = isFeeExempt_;

        emit adminAction("setFeeExempt", wallet_, isFeeExempt_ ? 1 : 0);
    }

    // Add to freeze exempt - Can move tokens while contract is frozen
    function setFreezeExempt(address wallet_, bool isFreezeExempt_) external onlyOwner {
        require(wallet_ != address(0), "Cannot exempt 0 address");
        isFreezeExempt[wallet_] = isFreezeExempt_;

        emit adminAction("setFreezeExempt", wallet_, isFreezeExempt_ ? 1 : 0);
    }

    // Add to process exempt - Will not process rewards on transactions
    function setProcessExempt(address wallet_, bool isProcessExempt_) external onlyOwner {
        require(wallet_ != address(0), "Cannot exempt 0 address");
        isProcessExempt[wallet_] = isProcessExempt_;

        emit adminAction("setProcessExempt", wallet_, isProcessExempt_ ? 1 : 0);
    }

    // Add to reward exempt - Does not receive rewards
    function setRewardExempt(address wallet_, bool isRwdExempt_) external onlyOwner {
        require(wallet_ != address(0), "Cannot exempt 0 address");
        isRwdExempt[wallet_] = isRwdExempt_;

        if(isRwdExempt_){
            rwdDistributor.setShare(wallet_, 0);
        }else{
            rwdDistributor.setShare(wallet_, balanceOf(wallet_));
        }

        emit adminAction("setRewardExempt", wallet_, isRwdExempt_ ? 1 : 0);
    }

    // Enable swapback and reward seeding
    function setSwapbackStatus(bool swapEnabled_) external onlyOwner {
        require(swapEnabled != swapEnabled_, "Status already set");
        swapEnabled = swapEnabled_;

        emit adminAction("setSwapbackStatus", address(0), swapEnabled_ ? 1 : 0);
    }

    // Adjust gas for processing rewards
    function setDistributorGas(uint256 distribGas_) external onlyOwner {
        require(distribGas_ >= 500_000, "Gas must be at least 500,000");
        distribGas = distribGas_;

        emit adminAction("setDistributorGas", address(0), distribGas_);
    }

    // Update taxes
    function updateTaxes(uint256 opsFee_, uint256 rwdFee_) external onlyOwner {
        require(rwdFee_ + opsFee_ <= 10, "Maximum total tax is 10%");
        rwdFee = rwdFee_;
        opsFee = opsFee_;

        totalTax = rwdFee_ + opsFee_;

        emit adminAction("updateTaxes", address(0), totalTax);
    }

    /*
     * Token Operations
     */
    // transfer function
    function _update(address sender_, address recipient_, uint256 amount_) internal override nonReentrant {
        require(sender_ != address(0) && recipient_ != address(0), "ERC20: zero address transfer");
        require(amount_ > 0, "Canot send 0 tokens");
        require(tradingActive || isFreezeExempt[sender_], "Contract not active");

        if (isFeeExempt[sender_] || isFeeExempt[recipient_] || (sender_ != tokenPair && recipient_ != tokenPair) || sender_ == address(this)) {
            super._update(sender_, recipient_, amount_);
        } else {
            uint256 taxAmount = (amount_ * totalTax) / 100;

            super._update(sender_, address(this), taxAmount);
            super._update(sender_, recipient_, amount_ - taxAmount);

            averageTX = (averageTX + amount_) / 2;
            swapThreshold = (averageTX * (totalTax * 3)) / 100;
        }

        if (swapEnabled && balanceOf(address(this)) > swapThreshold && sender_ != tokenPair) {
            distributeTax();
        }

        if(!isRwdExempt[sender_]){ rwdDistributor.setShare(sender_, balanceOf(sender_)); }
        if(!isRwdExempt[recipient_]){ rwdDistributor.setShare(recipient_, balanceOf(recipient_)); }

        if (tradingActive && !isProcessExempt[sender_]) {
            try rwdDistributor.process(distribGas) {
                emit tokenAction("Reward Process", address(rwdDistributor), distribGas, true);
            } catch {
                emit tokenAction("Reward Process", address(rwdDistributor), distribGas, false);
            }
        }
    }

    // Swap tokens for eth and send to receivers
    function distributeTax() internal nonReentrant {
        uint256 startWETH = address(this).balance;

        swapTokensForWETH(swapThreshold);

        uint256 taxWETH = address(this).balance - startWETH;
    
        uint256 opsWETH = taxWETH * (opsFee / totalTax);
        uint256 rwdWETH = taxWETH - opsWETH;

        if(opsWETH > 0) {
            (bool opsSuccess, ) = payable(opsReceiver).call{ value: opsWETH }("");
            emit tokenAction("Distribute Operations Wallet", opsReceiver, opsWETH, opsSuccess);
        }

        if(rwdWETH > 0) {
            (bool rwdSuccess, ) = payable(address(rwdDistributor)).call{ value: rwdWETH }("");
            emit tokenAction("Send WETH to distributor", address(rwdDistributor), rwdWETH, rwdSuccess);
        }

    }

    // Swap tokens for WETH
    function swapTokensForWETH(uint256 tokenAmount_) internal nonReentrant {
        address[] memory swapPath = new address[](2);
        swapPath[0] = address(this);
        swapPath[1] = tokenRouter.WETH();

        _approve(address(this), address(tokenRouter), tokenAmount_);

        tokenRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount_,
            0,
            swapPath,
            address(this),
            block.timestamp
        );
    }

}