// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;
pragma abicoder v2;

/*
 Optimization 100000
*/

import "./SwapHelper.sol";
import "./LiquidityHelper.sol";
import "./VaultStructInfo.sol";
import "./Ownable.sol";
import "./IERC20.sol";
import "./ReentrancyGuard.sol";
import "./IERC721Receiver.sol";
import "./IV3SwapRouter.sol";
import "./AaveHelper.sol";

contract Vault is IERC721Receiver, Ownable, ReentrancyGuard {
    using AaveHelper for AaveHelper.AaveInfo;
    using LiquidityHelper for LiquidityHelper.PositionMap;
    using VaultStructInfo for VaultStructInfo.BasicInfo;
    using VaultStructInfo for VaultStructInfo.TradingInfo;
    using VaultStructInfo for VaultStructInfo.TokenAllowedInfo;
    using VaultStructInfo for VaultStructInfo.UniInfo;
    
    LiquidityHelper.PositionMap private positionMap;
    VaultStructInfo.BasicInfo private basicInfo;
    VaultStructInfo.TradingInfo private tradingInfo;
    VaultStructInfo.TokenAllowedInfo private tokenAllowedInfo;
    VaultStructInfo.UniInfo private uniInfo;
    VaultStructInfo.ApproveInfo private approveInfo;
    mapping(uint256 => VaultStructInfo.LpRemoveRecord) private tokenIdLpInfoMap;
    AaveHelper.AaveInfo private aaveInfo;

    function initialize(string memory _vaultName, address _dispatcher, address[] memory allowTokens) external onlyOwner {
        basicInfo.initBasicInfo(_vaultName, _dispatcher, 0x5444bb8A081b527136F44F9c339CD3e515261e66);
        tradingInfo.initTradingInfo();
        uniInfo.initUniInfo();
        aaveInfo.initAaveInfo();
        tokenAllowedInfo.initTokenAllowedInfo(allowTokens);
    }

    function getVaultName() public view returns (string memory) {
        return basicInfo.vaultName;
    }

    function updateVaultName(string memory _newVaultName) external onlyOwner {
        basicInfo.vaultName = _newVaultName;
    }

    function onERC721Received(address /*operator*/, address, uint256 /*tokenId*/, bytes calldata) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    modifier dispatcherCheck() {
        require(basicInfo.dispatcher == msg.sender || owner() == msg.sender, "NA");
        _;
    }

    modifier onlyDispatcherCheck() {
        require(basicInfo.dispatcher == msg.sender, "NA");
        _;
    }

    modifier allowListCheck(address tokenAddress) {
        require(tokenAllowedInfo.tokenExists[tokenAddress].allowed, "NA");
        _;
    }


    /*
    * Swap
    */
    function swapInputETHForToken(address tokenOut, uint24 fee, uint256 amountIn, uint256 amountOutMin) external dispatcherCheck allowListCheck(tokenOut) returns (uint256 amountOut) {
        withdrawFromAaveForTrading(uniInfo.WETH, amountIn);
        amountOut = SwapHelper.swapInputETHForToken(tokenOut, fee, amountIn, amountOutMin, uniInfo.swapRouter, uniInfo.WETH);
        return tradingInfo.collectTradingFee(amountOut, tradingInfo.swapTradingFeeRate, tokenOut);
    }

    function swapInputForErc20Token(address tokenIn, address tokenOut, uint24 fee, uint256 amountIn, uint256 amountOutMin) external dispatcherCheck allowListCheck(tokenOut) returns (uint256 amountOut) {
        withdrawFromAaveForTrading(tokenIn, amountIn);
        amountOut = SwapHelper.swapInputForErc20Token(tokenIn, tokenOut, fee, amountIn, amountOutMin, uniInfo.swapRouter, approveInfo.swapApproveMap);
        return tradingInfo.collectTradingFee(amountOut, tradingInfo.swapTradingFeeRate, tokenOut);
    }

    function swapInputTokenToETH(address tokenIn, uint24 fee, uint256 amountIn, uint256 amountOutMin) external dispatcherCheck returns (uint256) {
        withdrawFromAaveForTrading(tokenIn, amountIn);
        return SwapHelper.swapInputTokenToETH(tokenIn, fee, amountIn, amountOutMin, uniInfo.swapRouter, uniInfo.WETH, approveInfo.swapApproveMap);
    }


    /*
    * Liquidity
    */
    function mintPosition(LiquidityHelper.CreateLpObject memory createLpObject) public dispatcherCheck allowListCheck(createLpObject.token0) allowListCheck(createLpObject.token1) {
        if (createLpObject.token0Amount == 0 || createLpObject.token1Amount == 0) {
            withdrawFromAaveForTrading(createLpObject.token0, createLpObject.token0Amount);
            withdrawFromAaveForTrading(createLpObject.token1, createLpObject.token1Amount);
        } else {
            withdrawAllFromAave(createLpObject.token0);
            withdrawAllFromAave(createLpObject.token1);
        }
        positionMap.mintNewPosition(createLpObject, uniInfo.nonfungiblePositionManager, approveInfo.liquidityApproveMap);
    }

    function mintPositions(LiquidityHelper.CreateLpObject[] memory createLpObject) external dispatcherCheck {
        for(uint16 i = 0; i < createLpObject.length; i++) {
            mintPosition(createLpObject[i]);
        }
    }

    function increaseLiquidity(uint256 positionId, uint256 token0Amount, uint256 token1Amount) external dispatcherCheck {
        if (token0Amount == 0 || token1Amount == 0) {
            withdrawFromAaveForTrading(positionMap.store[positionId].token0, token0Amount);
            withdrawFromAaveForTrading(positionMap.store[positionId].token1, token1Amount);
        } else {
            withdrawAllFromAave(positionMap.store[positionId].token0);
            withdrawAllFromAave(positionMap.store[positionId].token1);
        }
        LiquidityHelper.increaseLiquidityCurrentRange(uniInfo.nonfungiblePositionManager, positionId, token0Amount, token1Amount);
    }

    function removeAllPositionById(uint256 positionId) public dispatcherCheck {
        (uint256 amount0, uint256 amount1) = LiquidityHelper.removeAllPositionById(positionId, uniInfo.nonfungiblePositionManager);
        (uint256 amount0Fee, uint256 amount1Fee) = collectAllFeesInner(positionId, amount0, amount1);
        tokenIdLpInfoMap[positionId] = VaultStructInfo.LpRemoveRecord({
            token0: positionMap.store[positionId].token0,
            token1: positionMap.store[positionId].token1,
            token0Amount: amount0,
            token1Amount: amount1,
            token0FeeAmount: amount0Fee,
            token1FeeAmount: amount1Fee
        });
        positionMap.deleteDeposit(positionId);
    }

    function removeAllPositionByIds(uint256[] memory positionIds) external dispatcherCheck {
        for(uint16 i = 0; i < positionIds.length; i++) {
            removeAllPositionById(positionIds[i]);
        }
    }

    function removeLpInfoByTokenIds(uint256[] memory tokenIds) external dispatcherCheck {
        for(uint16 i = 0; i < tokenIds.length; i++) {
            delete tokenIdLpInfoMap[tokenIds[i]];
        }
    }

    function collectAllFees(uint256 positionId) external dispatcherCheck {
        collectAllFeesInner(positionId, 0, 0);
    }

    function burnNFT(uint128 tokenId) external dispatcherCheck {
        LiquidityHelper.burn(tokenId, uniInfo.nonfungiblePositionManager);
        positionMap.deleteDeposit(tokenId);
    }

    function collectAllFeesInner(uint256 positionId, uint256 amount0, uint256 amount1) internal returns (uint256 amount0Fee, uint256 amount1Fee) {
        (amount0Fee, amount1Fee) = LiquidityHelper.collectAllFees(positionId, uniInfo.nonfungiblePositionManager);
        tradingInfo.collectTradingFee(amount0Fee - amount0, tradingInfo.lpTradingFeeRate, positionMap.store[positionId].token0);
        tradingInfo.collectTradingFee(amount1Fee - amount1, tradingInfo.lpTradingFeeRate, positionMap.store[positionId].token1);
        return (amount0Fee - amount0, amount1Fee - amount1);
    }


    /*
    * Loan
    */
    function depositAllToAave() external dispatcherCheck {
        require(aaveInfo.autoStake, "NA");
        aaveInfo.depositAll(tokenAllowedInfo);
    }

    function withdrawAllFromAave() external dispatcherCheck {
        aaveInfo.withdrawAll(tokenAllowedInfo);
    }

    function withdrawFromAaveForTrading(address token, uint256 amountRequired) internal {
        if(aaveInfo.autoStake && tokenAllowedInfo.tokenExists[token].aTokenAddress != address(0)) {
            uint256 balance = IERC20(token).balanceOf(address(this));
            if (balance < amountRequired && IERC20(tokenAllowedInfo.tokenExists[token].aTokenAddress).balanceOf(address(this)) > (amountRequired - balance)) {
                aaveInfo.withdraw(token, amountRequired - balance);
            }
        }
    }

    function withdrawAllFromAave(address token) internal {
        if(aaveInfo.autoStake && tokenAllowedInfo.tokenExists[token].aTokenAddress != address(0)) {
            uint256 balance = IERC20(tokenAllowedInfo.tokenExists[token].aTokenAddress).balanceOf(address(this));
            if (balance > 0) {
                aaveInfo.withdraw(token, type(uint256).max);
            }
        }
    }

    function depositToAave(address token) internal {
        if(aaveInfo.autoStake && tokenAllowedInfo.tokenExists[token].aTokenAddress != address(0)) {
            uint256 balance = IERC20(token).balanceOf(address(this));
            aaveInfo.deposit(token, tokenAllowedInfo.tokenExists[token].aTokenAddress, balance);
        }
    }


    /*
    * Periphery functions
    */
    function setDispatcher(address _dispatcher) external onlyOwner {
        basicInfo.dispatcher = _dispatcher;
    }

    function setSwapAllowList(VaultStructInfo.AllowTokenObj[] memory _allowList) external onlyOwner {
        tokenAllowedInfo.setSwapAllowList(_allowList);
    }

    function updateTradingFee(uint8 _tradingFee) external onlyDispatcherCheck {
        require(_tradingFee <= 3, "TI");
        tradingInfo.tradingFee = _tradingFee;
    }

    function setAutoStake(bool _autoStake, VaultStructInfo.AllowTokenObj[] memory allowedTokens) external onlyOwner {
        aaveInfo.autoStake = _autoStake;
        tokenAllowedInfo.setSwapAllowList(allowedTokens);
        if (_autoStake) {
            aaveInfo.depositAll(tokenAllowedInfo);
        } else {
            aaveInfo.withdrawAll(tokenAllowedInfo);
        }
    }

    function claimRewards() external onlyOwner {
        tradingInfo.claimRewards();
    }


    /*
    * View functions
    */
    function getPositionIds() external view returns (uint256[] memory) {
        return positionMap.getAllKeys();
    }

    function getTokenIdByCustomerId(uint256 customerId) public view returns (uint256) {
        return positionMap.getTokenIdByCustomerId(customerId);
    }

    function queryRemovedLpInfo(uint256 tokenId) public view returns(VaultStructInfo.LpRemoveRecord memory) {
        return tokenIdLpInfoMap[tokenId];
    }

    function getAllowTokenList() public view returns (VaultStructInfo.AllowTokenObj[] memory) {
        return tokenAllowedInfo.allowList;
    }

    function balanceOf(bool isNativeToken, address token) public view returns(uint256) {
        if (isNativeToken) {
            return address(this).balance;
        }
        if (aaveInfo.autoStake) {
            uint256 balance = IERC20(token).balanceOf(address(this));
            uint256 aBalance = (tokenAllowedInfo.tokenExists[token].aTokenAddress == address(0)) ? 0 : IERC20(tokenAllowedInfo.tokenExists[token].aTokenAddress).balanceOf(address(this));
            return balance + aBalance;
        } else {
            return IERC20(token).balanceOf(address(this));
        }
    }

    function isAutoStake() public view returns(bool) {
        return aaveInfo.autoStake;
    }


    /*
    * Asset management
    */
    receive() external payable {}

    function withdrawErc721NFT(uint256 tokenId) external onlyOwner {
        uniInfo.nonfungiblePositionManager.safeTransferFrom(address(this), msg.sender, tokenId);
        positionMap.deleteDeposit(tokenId);
    }

    function withdrawTokens(address token, uint256 amount) external onlyOwner {
        withdrawFromAaveForTrading(token, amount);
        TransferHelper.safeTransfer(token, msg.sender, amount);
    }

    function withdrawETH(uint256 amount) external onlyOwner {
        TransferHelper.safeTransferETH(msg.sender, amount);
    }

    function deposit(address depositToken, uint256 amount) external onlyOwner {
        TransferHelper.safeTransferFrom(depositToken, msg.sender, address(this), amount);
        depositToAave(depositToken);
    }

    function depositEthToWeth() external payable onlyOwner {
        IWETH(uniInfo.WETH).deposit{value: msg.value}();
        depositToAave(uniInfo.WETH);
    }

    function depositGasToDispatcher(uint256 amount) external dispatcherCheck {
        IWETH(uniInfo.WETH).withdraw(amount);
        TransferHelper.safeTransferETH(basicInfo.dispatcher, amount);
    }

}
