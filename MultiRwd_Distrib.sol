//SPDX-License-Identifier: MIT

pragma solidity 0.8.27;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v5.1/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v5.1/contracts/access/Ownable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v5.1/contracts/utils/ReentrancyGuard.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v5.1/contracts/token/ERC20/utils/SafeERC20.sol";

interface iRouter {
    function WETH() external pure returns (address);
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable;
}

/*
 * Multi Reward Distributor
 * Developed by Kevin Remer (Totenmacher)
 */
contract Multi_RWD_Distributor is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public parentToken;

    uint256 public newRewardID;
    uint256[] public sendRewards;
    uint256[] public buyRewards;

    struct userRewardInfo {
        uint256 totalExcluded;
        uint256 totalRealised;
    }

    struct rewardTokenInfo {
        address tokenAddress;
        uint256 totalDividends;
        uint256 totalDistributed;
        uint256 dividendsPerShare;
        bool isActive;
    }

    iRouter rewardRouter;

    mapping(uint256 => rewardTokenInfo) public rewardTokens;

    address[] shareholders;
    mapping(address => uint256) shareholderIndexes;
    mapping(address => uint256) public userShares;
    mapping(uint256 => mapping(address => userRewardInfo)) public userRewards;

    uint256 public totalShares;
    uint256 public dividendsPerShareAccuracyFactor;

    uint256 public wethRewardBalance;

    uint256 public swapWETHThreshold;

    uint256 currentIndex;

    modifier onlyToken() {
        require(msg.sender == parentToken || msg.sender == owner()); _;
    }

    event sendRwd(address receiver, uint256 rwdAmount, bool result);
    event adminAction(string Action, address Address, uint256 Amount);

    constructor(address parentToken_, address rewardRouter_) Ownable(msg.sender) {
        parentToken = parentToken_;

        rewardRouter = iRouter(rewardRouter_);

        dividendsPerShareAccuracyFactor = 10 ** 36;
        swapWETHThreshold = .5 * (10 ** 18);
    }

    receive() external payable {}

    fallback() external payable {}

    /*
     * Admin functions
     */

    // Clear WETH from contract
    function harvestWETH() external onlyOwner nonReentrant {
        uint256 curRewardToken;
        uint256 sendAmount = address(this).balance;

        for(uint256 art = 0; art < sendRewards.length; art++) {
            curRewardToken = sendRewards[art];

            if(rewardTokens[curRewardToken].tokenAddress == rewardRouter.WETH() && rewardTokens[curRewardToken].isActive == true) {
                uint256 undistBalance = rewardTokens[curRewardToken].totalDividends - rewardTokens[curRewardToken].totalDistributed;
                require(address(this).balance > undistBalance, "Cannot remove undistributed reward tokens");

                sendAmount = address(this).balance - undistBalance;

                break;
            }
        }

        (bool sendSuccess, ) = payable(owner()).call{value: sendAmount}("");

        if(sendSuccess) {
            emit adminAction("harvestWETH", address(0), sendAmount);
        } else {
            emit adminAction("harvestWETH", address(0), 0);
        }

    }

    // Remove full balance of given token
    function clearStuckToken(address tokenAddress_) external onlyOwner nonReentrant {
        uint256 curRewardToken;
        uint256 sendAmount = IERC20(tokenAddress_).balanceOf(address(this));

        for(uint256 art = 0; art < sendRewards.length; art++) {
            curRewardToken = sendRewards[art];

            if(rewardTokens[curRewardToken].tokenAddress == tokenAddress_ && rewardTokens[curRewardToken].isActive == true) {
                uint256 undistBalance = rewardTokens[curRewardToken].totalDividends - rewardTokens[curRewardToken].totalDistributed;
                require(IERC20(tokenAddress_).balanceOf(address(this)) > undistBalance, "Cannot remove undistributed reward tokens");

                sendAmount = IERC20(tokenAddress_).balanceOf(address(this)) - undistBalance;

                break;
            }
        }

        IERC20(tokenAddress_).safeTransfer(owner(), sendAmount);

        emit adminAction("clearStuckToken", tokenAddress_, sendAmount);
    }

    // Add reward token to contract
    function addRewardToken(address rewardToken_) external onlyOwner {
        uint256 curRewardToken;
        
        for(uint256 art = 0; art < sendRewards.length; art++) {
            curRewardToken = sendRewards[art];

            if(rewardTokens[curRewardToken].tokenAddress == rewardToken_) {
                require(rewardTokens[curRewardToken].tokenAddress != rewardToken_, "That reward token already exists");

                break;
            }
        }

        buyRewards.push(newRewardID);
        sendRewards.push(newRewardID);
        rewardTokens[newRewardID].tokenAddress = rewardToken_;

        emit adminAction("addRewardToken", rewardToken_, newRewardID);

        newRewardID++;
    }

    // Remove reward token from being actively bought
    function deactivateRewardToken(address tokenAddress_) external onlyOwner {
        uint256 curRewardToken;
        bool tokenFound;

        for(uint256 drt = 0; drt < buyRewards.length; drt++) {
            curRewardToken = buyRewards[drt];

            if(rewardTokens[curRewardToken].tokenAddress == tokenAddress_) {
                rewardTokens[curRewardToken].isActive = false;

                tokenFound = true;

                buyRewards[drt] = buyRewards[buyRewards.length-1];
                buyRewards.pop();

                emit adminAction("deactivateRewardToken", tokenAddress_, curRewardToken);

                return;
            }
        }

        if(!tokenFound) {
            require(tokenFound, "Token is not active");
        }

    }

    // Reactivate reward token that hasn't fully distributed
    function reactivateRewardToken(address tokenAddress_) external onlyOwner {
        uint256 curRewardToken;
        bool tokenFound;

        for(uint256 rrt = 0; rrt < sendRewards.length; rrt++) {
            curRewardToken = sendRewards[rrt];

            if(rewardTokens[curRewardToken].tokenAddress == tokenAddress_) {
                rewardTokens[curRewardToken].isActive = true;

                tokenFound = true;

                buyRewards.push(curRewardToken);

                emit adminAction("reactivateRewardToken", tokenAddress_, curRewardToken);

                return;
            }
        }

        if(!tokenFound) {
            require(tokenFound, "Token not found");
        }
    }

    // Set the address of the token contract that can call on the distributor
    function setParentToken(address parentToken_) external onlyOwner {
        parentToken = parentToken_;
    }

    // Set the threshold of WETH at which to acquire more reward tokens
    function setWETHThreshold(uint256 swapWETHThreshold_) external onlyOwner {
        swapWETHThreshold = swapWETHThreshold_;
    }

    // Set the address of the router to be used to buy more reward tokens
    function updateRewardRouter(address rewardRouter_) external onlyOwner {
        rewardRouter = iRouter(rewardRouter_);
    }

    /*
     * External calls from parent token
     */
    function setShare(address shareholder_, uint256 amount_) external onlyToken {
        if(userShares[shareholder_] > 0){
            distributeDividend(shareholder_);
        }

        if(amount_ > 0 && userShares[shareholder_] == 0){
            addShareholder(shareholder_);
        }else if(amount_ == 0 && userShares[shareholder_] > 0){
            removeShareholder(shareholder_);
        }

        totalShares = totalShares - userShares[shareholder_] + amount_;
        userShares[shareholder_] = amount_;

        uint256 curRewardToken;
        for(uint256 ss = 0; ss < sendRewards.length; ss++) {
            curRewardToken = sendRewards[ss];
            userRewards[curRewardToken][shareholder_].totalExcluded = getCumulativeDividends(userShares[shareholder_], curRewardToken);
        }
    }

    // Loop through holders and distribute as needed, or acquire more reward tokens
    function process(uint256 gas_) external {
        if(address(this).balance > swapWETHThreshold - wethRewardBalance) {
            processWETH();
            return;
        }

        uint256 shareholderCount = shareholders.length;

        if(shareholderCount == 0) { return; }

        uint256 gasUsed = 0;
        uint256 gasLeft = gasleft();

        uint256 iterations = 0;

        while(gasUsed < gas_ && iterations < shareholderCount) {
            if(currentIndex >= shareholderCount){
                currentIndex = 0;
            }

            distributeDividend(shareholders[currentIndex]);

            gasUsed = gasUsed + gasLeft - gasleft();
            gasLeft = gasleft();
            unchecked {
                currentIndex++;
                iterations++;
            }
        }
    }

    /*
     * Internal functions
     */
    // Remove inactive reward token from sendRewards if supply of reward tokens has been fully distributed
    function removeCompleteRewards() internal {
        uint256 curRewardToken;

        for(uint256 rcr = 0; rcr < sendRewards.length; rcr++) {
            curRewardToken = sendRewards[rcr];

            if(rewardTokens[curRewardToken].isActive == false && rewardTokens[curRewardToken].totalDistributed == rewardTokens[curRewardToken].totalDividends) {
                sendRewards[rcr] = sendRewards[sendRewards.length-1];
                sendRewards.pop();
            }
        }
    }

    // Acquire more reward tokens for each token in buyRewards
    function processWETH() internal {
        uint256 wethPerReward = (address(this).balance - wethRewardBalance) / buyRewards.length;

        uint256 curRewardToken;

        for(uint256 cbr = 0; cbr < buyRewards.length; cbr++) {
            curRewardToken = buyRewards[cbr];

            if(rewardTokens[curRewardToken].tokenAddress == rewardRouter.WETH()) {
                rewardTokens[curRewardToken].totalDividends = rewardTokens[curRewardToken].totalDividends + wethPerReward;
                rewardTokens[curRewardToken].dividendsPerShare = rewardTokens[curRewardToken].dividendsPerShare + (dividendsPerShareAccuracyFactor * wethPerReward / totalShares);
            } else {
                uint256 balanceBefore = IERC20(rewardTokens[curRewardToken].tokenAddress).balanceOf(address(this));

                address[] memory path = new address[](2);
                path[0] = rewardRouter.WETH();
                path[1] = rewardTokens[curRewardToken].tokenAddress;

                rewardRouter.swapExactETHForTokensSupportingFeeOnTransferTokens{value: wethPerReward}(
                    0,
                    path,
                    address(this),
                    block.timestamp
                );

                uint256 amount = IERC20(rewardTokens[curRewardToken].tokenAddress).balanceOf(address(this)) - balanceBefore;

                rewardTokens[curRewardToken].totalDividends = rewardTokens[curRewardToken].totalDividends + amount;
                rewardTokens[curRewardToken].dividendsPerShare = rewardTokens[curRewardToken].dividendsPerShare + (dividendsPerShareAccuracyFactor * amount / totalShares);
            }
        }

        removeCompleteRewards();
    }

    // Send specified holder all of their owed rewards
    function distributeDividend(address shareholder_) internal {
        if(userShares[shareholder_] == 0){ return; }

        uint256 curRewardToken;

        for(uint256 csr = 0; csr < sendRewards.length; csr++) {
            curRewardToken = sendRewards[csr];

            uint256 amount = getUnpaidEarnings(shareholder_, curRewardToken);

            if(amount > 0){
                rewardTokens[curRewardToken].totalDistributed = rewardTokens[curRewardToken].totalDistributed + amount;
                if(rewardTokens[curRewardToken].tokenAddress == rewardRouter.WETH()) {
                    (bool sendSuccess, ) = payable(shareholder_).call{value: amount}("");
                    emit sendRwd(shareholder_, amount, sendSuccess);
                } else {
                    IERC20(rewardTokens[curRewardToken].tokenAddress).transfer(shareholder_, amount);
                    emit sendRwd(shareholder_, amount, true);
                }

                userRewards[curRewardToken][shareholder_].totalRealised = userRewards[curRewardToken][shareholder_].totalRealised + amount;
                userRewards[curRewardToken][shareholder_].totalExcluded = getCumulativeDividends(userShares[shareholder_], curRewardToken);
            }
        }
    }

    // Get full reward amount owed for a given reward token based on share size
    function getCumulativeDividends(uint256 share_, uint256 rewardTokenID) internal view returns (uint256) {
        return share_ * rewardTokens[rewardTokenID].dividendsPerShare / dividendsPerShareAccuracyFactor;
    }

    // Add new holder to the distributor
    function addShareholder(address shareholder_) internal {
        shareholderIndexes[shareholder_] = shareholders.length;
        shareholders.push(shareholder_);
    }

    // Remove holder from the distributor
    function removeShareholder(address shareholder_) internal {
        shareholders[shareholderIndexes[shareholder_]] = shareholders[shareholders.length-1];
        shareholderIndexes[shareholders[shareholders.length-1]] = shareholderIndexes[shareholder_];
        shareholders.pop();
    }

    /*
     * Public functions
     */
    // Allows holder to manually claim all rewards they are owed
    function claimDividend() external {
        distributeDividend(msg.sender);
    }
    
    // Returns the unpaid rewards for a given reward token, for a given holder
    function getUnpaidEarnings(address shareholder_, uint256 rewardTokenID) public view returns (uint256) {
        if(userShares[shareholder_] == 0){ return 0; }

        uint256 shareholderTotalDividends = getCumulativeDividends(userShares[shareholder_], rewardTokenID);
        uint256 shareholderTotalExcluded = userRewards[rewardTokenID][shareholder_].totalExcluded;

        if(shareholderTotalDividends <= shareholderTotalExcluded){ return 0; }

        return shareholderTotalDividends - shareholderTotalExcluded;
    }

}