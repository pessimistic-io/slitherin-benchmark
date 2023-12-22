// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity 0.8.17;

import "./CamelotRewardHelper.sol";
import "./SYBaseWithRewards.sol";
import "./CamelotV1VolatilePreview.sol";
import "./CamelotV1VolatileLpHelper.sol";

contract PendleCamelotV1VolatileSY is
    SYBaseWithRewards,
    CamelotRewardHelper,
    CamelotV1VolatileLpHelper
{
    using Math for uint256;
    using ArrayLib for address[];

    address[] public rewardTokens;
    CamelotV1VolatilePreview public immutable previewHelper;
    bool public isRewardDisabled;

    constructor(
        string memory _name,
        string memory _symbol,
        address _pair,
        address _factory,
        address _router,
        address _nitroPool,
        address _referrer,
        CamelotV1VolatilePreview _previewHelper
    )
        CamelotV1VolatileLpHelper(_pair, _factory, _router, _referrer)
        SYBaseWithRewards(_name, _symbol, _pair)
        CamelotRewardHelper(_nitroPool, _pair)
    {
        rewardTokens.push(GRAIL);
        updateRewardTokensList();
        previewHelper = _previewHelper;
    }

    /**
     * @dev See {SYBase-_deposit}
     */
    function _deposit(address tokenIn, uint256 amountDeposited)
        internal
        virtual
        override
        returns (uint256)
    {
        uint256 amountLpDeposited;
        if (tokenIn == pair) {
            amountLpDeposited = amountDeposited;
        } else {
            amountLpDeposited = _zapIn(tokenIn, amountDeposited);
        }

        if (isRewardDisabled) {
            return amountLpDeposited;
        } else {
            return _increaseNftPoolPosition(amountLpDeposited);
        }
    }

    /**
     * @dev See {SYBase-_redeem}
     */
    function _redeem(
        address receiver,
        address tokenOut,
        uint256 amountSharesToRedeem
    ) internal virtual override returns (uint256 amountTokenOut) {
        // solhint-disable-next-line
        if (isRewardDisabled) {
            // if isRewardDisabled is activated, the LP has been withdrawn from the pool
        } else {
            _decreaseNftPoolPosition(amountSharesToRedeem);
        }

        if (tokenOut == pair) {
            amountTokenOut = amountSharesToRedeem;
        } else {
            amountTokenOut = _zapOut(tokenOut, amountSharesToRedeem);
        }
        _transferOut(tokenOut, receiver, amountTokenOut);
    }

    function exchangeRate() public view virtual override returns (uint256) {
        (uint256 reserve0, uint256 reserve1, , ) = ICamelotPair(pair).getReserves();
        uint256 supply = ICamelotPair(pair).totalSupply();
        return Math.sqrt(reserve0 * reserve1).divDown(supply);
    }

    /*///////////////////////////////////////////////////////////////
                               REWARDS-RELATED
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev See {IStandardizedYield-getRewardTokens}
     */
    function _getRewardTokens() internal view virtual override returns (address[] memory res) {
        return rewardTokens;
    }

    /// @notice allows anyone to add new rewardTokens to this SY if a new rewardToken is added to the Nitro pool
    function updateRewardTokensList() public virtual {
        address token1 = ICamelotNitroPool(nitroPool).rewardsToken1().token;
        address token2 = ICamelotNitroPool(nitroPool).rewardsToken2().token;

        if (token1 != address(0) && !rewardTokens.contains(token1)) rewardTokens.push(token1);
        if (token2 != address(0) && !rewardTokens.contains(token2)) rewardTokens.push(token2);
    }

    function _redeemExternalReward() internal override {
        if (isRewardDisabled) {
            return;
        }

        ICamelotNitroPool(nitroPool).harvest();
        ICamelotNFTPool(nftPool).harvestPosition(positionId);
        _allocateXGrail();
    }

    /*///////////////////////////////////////////////////////////////
                    PREVIEW-RELATED
    //////////////////////////////////////////////////////////////*/

    function _previewDeposit(address tokenIn, uint256 amountTokenToDeposit)
        internal
        view
        override
        returns (uint256)
    {
        if (tokenIn == pair) {
            return amountTokenToDeposit;
        } else {
            return previewHelper.previewZapIn(_getPairData(), tokenIn, amountTokenToDeposit);
        }
    }

    function _previewRedeem(address tokenOut, uint256 amountSharesToRedeem)
        internal
        view
        override
        returns (uint256)
    {
        if (tokenOut == pair) {
            return amountSharesToRedeem;
        } else {
            return previewHelper.previewZapOut(_getPairData(), tokenOut, amountSharesToRedeem);
        }
    }

    function _getPairData() internal view returns (CamelotPairData memory data) {
        data.token0 = token0;
        data.token1 = token1;
        data.pair = pair;
        (data.reserve0, data.reserve1, data.fee0, data.fee1) = ICamelotPair(pair).getReserves();
    }

    /*///////////////////////////////////////////////////////////////
                MISC FUNCTIONS FOR METADATA
    //////////////////////////////////////////////////////////////*/

    function getTokensIn() public view virtual override returns (address[] memory res) {
        res = new address[](3);
        res[0] = token0;
        res[1] = token1;
        res[2] = pair;
    }

    function getTokensOut() public view virtual override returns (address[] memory res) {
        res = new address[](3);
        res[0] = token0;
        res[1] = token1;
        res[2] = pair;
    }

    function isValidTokenIn(address token) public view virtual override returns (bool) {
        return token == token0 || token == token1 || token == pair;
    }

    function isValidTokenOut(address token) public view virtual override returns (bool) {
        return token == token0 || token == token1 || token == pair;
    }

    function assetInfo()
        external
        view
        returns (
            AssetType assetType,
            address assetAddress,
            uint8 assetDecimals
        )
    {
        return (AssetType.LIQUIDITY, pair, IERC20Metadata(pair).decimals());
    }

    /*///////////////////////////////////////////////////////////////
                        OWNER ONLY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Use emergencyWithdraw to ensure LP withdrawal is always successful
    function setRewardDisabled(bool doRewardIndexUpdate) external onlyOwner {
        if (doRewardIndexUpdate) _updateRewardIndex();

        if (positionId != POSITION_UNINITIALIZED) {
            ICamelotNitroPool(nitroPool).emergencyWithdraw(positionId);
            ICamelotNFTPool(nftPool).emergencyWithdraw(positionId);
            positionId = POSITION_UNINITIALIZED;
        }

        isRewardDisabled = true;
    }

    function setReferrerForSwap(address newReferrer) external onlyOwner {
        referrerForSwap = newReferrer;
    }

    // XGRAIL related, to be used only when this SY is deprecated

    function redeemXGrailOwner(uint256 xGrailAmount, uint256 duration) external onlyOwner {
        IXGrail(xGRAIL).redeem(xGrailAmount, duration);
    }

    function finalizeRedeem(uint256 redeemIndex) external onlyOwner {
        uint256 preBalance = _selfBalance(GRAIL);

        IXGrail(xGRAIL).finalizeRedeem(redeemIndex);

        uint256 amount = _selfBalance(GRAIL) - preBalance;
        _transferOut(GRAIL, msg.sender, amount);
    }

    function cancelRedeem(uint256 redeemIndex) external onlyOwner {
        IXGrail(xGRAIL).cancelRedeem(redeemIndex);
    }
}

