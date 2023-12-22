// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "./IERC20.sol";
import "./IDToken.sol";
import "./IMarket.sol";
import "./IVault.sol";
import "./IOracleManager.sol";
import "./ISwapper.sol";
import "./ISymbolManager.sol";
import "./IPrivileger.sol";
import "./IRewardVault.sol";
import "./PoolStorage.sol";
import "./NameVersion.sol";
import "./SafeMath.sol";
import "./SafeERC20.sol";

contract PoolImplementation is PoolStorage, NameVersion {

    event CollectProtocolFee(address indexed collector, uint256 amount);

    event AddMarket(address indexed market);

    event SetRouter(address router, bool isActive);

    event AddLiquidity(
        uint256 indexed lTokenId,
        address indexed asset,
        uint256 amount,
        int256 newLiquidity
    );

    event RemoveLiquidity(
        uint256 indexed lTokenId,
        address indexed asset,
        uint256 amount,
        int256 newLiquidity
    );

    event AddMargin(
        uint256 indexed pTokenId,
        address indexed asset,
        uint256 amount,
        int256 newMargin
    );

    event RemoveMargin(
        uint256 indexed pTokenId,
        address indexed asset,
        uint256 amount,
        int256 newMargin
    );

    using SafeMath for uint256;
    using SafeMath for int256;
    using SafeERC20 for IERC20;

    int256 constant ONE = 1e18;
    uint256 constant UONE = 1e18;
    uint256 constant UMAX = type(uint256).max / UONE;

    address public immutable vaultTemplate;

    address public immutable vaultImplementation;

    address public immutable tokenB0;

    address public immutable tokenWETH;

    address public immutable marketB0;

    address public immutable marketWETH;

    IDToken public immutable lToken;

    IDToken public immutable pToken;

    IOracleManager public immutable oracleManager;

    ISwapper public immutable swapper;

    ISymbolManager public immutable symbolManager;

    IPrivileger public immutable privileger;

    IRewardVault public immutable rewardVault;

    uint8 public immutable decimalsB0;

    uint256 public immutable reserveRatioB0;

    int256 public immutable minRatioB0;

    int256 public immutable poolInitialMarginMultiplier;

    int256 public immutable protocolFeeCollectRatio;

    int256 public immutable minLiquidationReward;

    int256 public immutable maxLiquidationReward;

    int256 public immutable liquidationRewardCutRatio;

    constructor (
        address[13] memory addresses_,
        uint256[7] memory parameters_
    ) NameVersion('PoolImplementation', '3.0.2')
    {
        vaultTemplate = addresses_[0];
        vaultImplementation = addresses_[1];
        tokenB0 = addresses_[2];
        tokenWETH = addresses_[3];
        marketB0 = addresses_[4];
        marketWETH = addresses_[5];
        lToken = IDToken(addresses_[6]);
        pToken = IDToken(addresses_[7]);
        oracleManager = IOracleManager(addresses_[8]);
        swapper = ISwapper(addresses_[9]);
        symbolManager = ISymbolManager(addresses_[10]);
        privileger = IPrivileger(addresses_[11]);
        rewardVault = IRewardVault(addresses_[12]);

        decimalsB0 = IERC20(tokenB0).decimals();

        reserveRatioB0 = parameters_[0];
        minRatioB0 = parameters_[1].utoi();
        poolInitialMarginMultiplier = parameters_[2].utoi();
        protocolFeeCollectRatio = parameters_[3].utoi();
        minLiquidationReward = parameters_[4].utoi();
        maxLiquidationReward = parameters_[5].utoi();
        liquidationRewardCutRatio = parameters_[6].utoi();
    }

    function addMarket(address market) external _onlyAdmin_ {
        // asset is the underlying token of Aave market
        address asset = IMarket(market).UNDERLYING_ASSET_ADDRESS();
        require(
            IMarket(market).POOL() == IVault(vaultImplementation).aavePool(),
            'PI: wrong Aave pool'
        );
        require(
            swapper.isSupportedToken(asset),
            'PI: no swapper support'
        );
        require(
            markets[asset] == address(0),
            'PI: replace not allowed'
        );

        markets[asset] = market;
        approveSwapper(asset);

        emit AddMarket(market);
    }

    function approveSwapper(address asset) public _onlyAdmin_ {
        uint256 allowance = IERC20(asset).allowance(address(this), address(swapper));
        if (allowance != type(uint256).max) {
            if (allowance != 0) {
                IERC20(asset).safeApprove(address(swapper), 0);
            }
            IERC20(asset).safeApprove(address(swapper), type(uint256).max);
        }
    }

    function setRouter(address router_, bool isActive) external _onlyAdmin_ {
        isRouter[router_] = isActive;
        emit SetRouter(router_, isActive);
    }

    function collectProtocolFee() external {
        require(protocolFeeCollector != address(0), 'PI: collector not set');
        // rescale protocolFeeAccrued from decimals18 to decimalsB0
        (uint256 amount, uint256 remainder) = protocolFeeAccrued.itou().rescaleDown(18, decimalsB0);
        protocolFeeAccrued = remainder.utoi();
        IERC20(tokenB0).safeTransfer(protocolFeeCollector, amount);
        emit CollectProtocolFee(protocolFeeCollector, amount);
    }

    function claimStakedAaveLp(address reward, address account) external {
        uint256 lTokenId = lToken.getTokenIdOf(account);
        if (lTokenId != 0) {
            IVault vault = IVault(lpInfos[lTokenId].vault);
            address[] memory assetsIn = vault.getAssetsIn();
            address[] memory marketsIn = new address[](assetsIn.length);
            for (uint256 i = 0; i < assetsIn.length; i++) {
                marketsIn[i] = markets[assetsIn[i]];
            }
            vault.claimStakedAave(marketsIn, reward, account);
        }
    }

    function claimStakedAaveTrader(address reward, address account) external {
        uint256 pTokenId = pToken.getTokenIdOf(account);
        if (pTokenId != 0) {
            IVault vault = IVault(tdInfos[pTokenId].vault);
            address[] memory assetsIn = vault.getAssetsIn();
            address[] memory marketsIn = new address[](assetsIn.length);
            for (uint256 i = 0; i < assetsIn.length; i++) {
                marketsIn[i] = markets[assetsIn[i]];
            }
            vault.claimStakedAave(marketsIn, reward, account);
        }
    }

    //================================================================================

    // amount in asset's own decimals
    function addLiquidity(address asset, uint256 amount, OracleSignature[] memory oracleSignatures) external payable _reentryLock_
    {
        _updateOracles(oracleSignatures);

        if (asset == address(0)) amount = msg.value;

        Data memory data = _initializeDataWithAccount(msg.sender, asset);
        _getLpInfo(data, true);

        ISymbolManager.SettlementOnAddLiquidity memory s =
        symbolManager.settleSymbolsOnAddLiquidity(data.liquidity + data.lpsPnl);

        int256 undistributedPnl = s.funding - s.deltaTradersPnl;
        if (undistributedPnl != 0) {
            data.lpsPnl += undistributedPnl;
            data.cumulativePnlPerLiquidity += undistributedPnl * ONE / data.liquidity;
        }

        uint256 balanceB0 = IERC20(tokenB0).balanceOf(address(this));
        _settleLp(data);
        _transferIn(data, amount);
        int256 newLiquidity = IVault(data.vault).getVaultLiquidity().utoi() + data.amountB0;

        if (address(rewardVault) != address(0)) {
            uint256 assetBalanceB0 = IVault(data.vault).getAssetBalance(marketB0);
            int256 newLiquidityB0 = assetBalanceB0.rescale(decimalsB0, 18).utoi() + data.amountB0;
            newLiquidityB0 = newLiquidity >= newLiquidityB0 ? newLiquidityB0 : newLiquidity;
            rewardVault.updateVault(data.liquidity.itou(), data.tokenId, data.lpLiquidity.itou(), balanceB0.rescale(decimalsB0, 18), newLiquidityB0);
        }

        data.liquidity += newLiquidity - data.lpLiquidity;
        data.lpLiquidity = newLiquidity;

        // only check B0 sufficiency when underlying is not B0
        if (asset != tokenB0) {
            require(
                // rescale tokenB0 balance from decimalsB0 to 18
                IERC20(tokenB0).balanceOf(address(this)).rescale(decimalsB0, 18).utoi() * ONE >= data.liquidity * minRatioB0,
                'PI: insufficient B0'
            );
        }

        liquidity = data.liquidity;
        lpsPnl = data.lpsPnl;
        cumulativePnlPerLiquidity = data.cumulativePnlPerLiquidity;

        LpInfo storage info = lpInfos[data.tokenId];
        info.vault = data.vault;
        info.amountB0 = data.amountB0;
        info.liquidity = data.lpLiquidity;
        info.cumulativePnlPerLiquidity = data.lpCumulativePnlPerLiquidity;

        emit AddLiquidity(data.tokenId, asset, amount, newLiquidity);
    }

    // amount in asset's own decimals
    function removeLiquidity(address asset, uint256 amount, OracleSignature[] memory oracleSignatures) external _reentryLock_
    {
        _updateOracles(oracleSignatures);

        Data memory data = _initializeDataWithAccount(msg.sender, asset);
        _getLpInfo(data, false);

        int256 removedLiquidity;
        uint256 assetBalance = IVault(data.vault).getAssetBalance(data.market);
        if (asset == tokenB0) {
            int256 available = assetBalance.rescale(decimalsB0, 18).utoi() + data.amountB0; // available in decimals18
            if (available > 0) {
                removedLiquidity = amount >= UMAX ?
                                   available :
                                   available.min(amount.rescale(decimalsB0, 18).utoi());
            }
        } else if (assetBalance > 0) {
            uint256 redeemAmount = amount.min(assetBalance);
            removedLiquidity = IVault(data.vault).getHypotheticalVaultLiquidityChange(data.asset, redeemAmount).utoi();
        }

        require(data.liquidity + data.lpsPnl > removedLiquidity, 'PI: removedLiquidity > total liquidity');
        ISymbolManager.SettlementOnRemoveLiquidity memory s =
        symbolManager.settleSymbolsOnRemoveLiquidity(data.liquidity + data.lpsPnl, removedLiquidity);
        require(s.removeLiquidityPenalty >= 0, 'PI: negative penalty');

        int256 undistributedPnl = s.funding - s.deltaTradersPnl + s.removeLiquidityPenalty;
        data.lpsPnl += undistributedPnl;
        data.cumulativePnlPerLiquidity += undistributedPnl * ONE / data.liquidity;
        data.amountB0 -= s.removeLiquidityPenalty;

        _settleLp(data);

        uint256 balanceB0 = IERC20(tokenB0).balanceOf(address(this));
        uint256 newVaultLiquidity = _transferOut(data, amount, assetBalance);
        int256 newLiquidity = newVaultLiquidity.utoi() + data.amountB0;

        if (address(rewardVault) != address(0)) {
            uint256 assetBalanceB0 = IVault(data.vault).getAssetBalance(marketB0);
            int256 newLiquidityB0 = assetBalanceB0.rescale(decimalsB0, 18).utoi() + data.amountB0;
            newLiquidityB0 = newLiquidity >= newLiquidityB0 ? newLiquidityB0 : newLiquidity;
            rewardVault.updateVault(data.liquidity.itou(), data.tokenId, data.lpLiquidity.itou(), balanceB0.rescale(decimalsB0, 18), newLiquidityB0);
        }

        data.liquidity += newLiquidity - data.lpLiquidity;
        data.lpLiquidity = newLiquidity;

        require(
            data.liquidity * ONE >= s.initialMarginRequired * poolInitialMarginMultiplier,
            'PI: pool insufficient liquidity'
        );

        liquidity = data.liquidity;
        lpsPnl = data.lpsPnl;
        cumulativePnlPerLiquidity = data.cumulativePnlPerLiquidity;

        LpInfo storage info = lpInfos[data.tokenId];
        info.amountB0 = data.amountB0;
        info.liquidity = data.lpLiquidity;
        info.cumulativePnlPerLiquidity = data.lpCumulativePnlPerLiquidity;

        emit RemoveLiquidity(data.tokenId, asset, amount, newLiquidity);
    }

    // amount in asset's own decimals
    function addMargin(address account, address asset, uint256 amount, OracleSignature[] memory oracleSignatures) external payable _reentryLock_
    {   if (!isRouter[msg.sender]) {
            require(account == msg.sender, "PI: unauthorized call");
        }

        _updateOracles(oracleSignatures);

        if (asset == address(0)) amount = msg.value;

        Data memory data;
        data.asset = asset;
        data.decimalsAsset = _getDecimalsAsset(asset); // get asset's decimals
        data.market = _getMarket(asset);
        data.account = account;

        _getTdInfo(data, true);
        _transferIn(data, amount);

        int256 newMargin = IVault(data.vault).getVaultLiquidity().utoi() + data.amountB0;

        TdInfo storage info = tdInfos[data.tokenId];
        info.vault = data.vault;
        info.amountB0 = data.amountB0;

        emit AddMargin(data.tokenId, asset, amount, newMargin);
    }

    // amount in asset's own decimals
    function removeMargin(address account, address asset, uint256 amount, OracleSignature[] memory oracleSignatures) external _reentryLock_
    {
        if (!isRouter[msg.sender]) {
            require(account == msg.sender, "PI: unauthorized call");
        }

        _updateOracles(oracleSignatures);

        Data memory data = _initializeDataWithAccount(account, asset);
        _getTdInfo(data, false);

        ISymbolManager.SettlementOnRemoveMargin memory s =
        symbolManager.settleSymbolsOnRemoveMargin(data.tokenId, data.liquidity + data.lpsPnl);

        int256 undistributedPnl = s.funding - s.deltaTradersPnl;
        data.lpsPnl += undistributedPnl;
        data.cumulativePnlPerLiquidity += undistributedPnl * ONE / data.liquidity;

        data.amountB0 -= s.traderFunding;

        uint256 assetBalance = IVault(data.vault).getAssetBalance(data.market);
        int256 newVaultLiquidity = _transferOut(data, amount, assetBalance).utoi();

        require(
            newVaultLiquidity + data.amountB0 + s.traderPnl >= s.traderInitialMarginRequired,
            'PI: insufficient margin'
        );

        lpsPnl = data.lpsPnl;
        cumulativePnlPerLiquidity = data.cumulativePnlPerLiquidity;

        tdInfos[data.tokenId].amountB0 = data.amountB0;

        emit RemoveMargin(data.tokenId, asset, amount, newVaultLiquidity + data.amountB0);
    }

    function trade(address account, string memory symbolName, int256 tradeVolume, int256 priceLimit) external _reentryLock_
    {
        require(isRouter[msg.sender], 'PI: only router');
        bytes32 symbolId = keccak256(abi.encodePacked(symbolName));

        Data memory data = _initializeDataWithAccount(account);
        _getTdInfo(data, false);

        ISymbolManager.SettlementOnTrade memory s =
        symbolManager.settleSymbolsOnTrade(data.tokenId, symbolId, tradeVolume, data.liquidity + data.lpsPnl, priceLimit);

        int256 collect = s.tradeFee * protocolFeeCollectRatio / ONE;
        int256 undistributedPnl = s.funding - s.deltaTradersPnl + s.tradeFee - collect + s.tradeRealizedCost;
        data.lpsPnl += undistributedPnl;
        data.cumulativePnlPerLiquidity += undistributedPnl * ONE / data.liquidity;

        data.amountB0 -= s.traderFunding + s.tradeFee + s.tradeRealizedCost;
        int256 margin = IVault(data.vault).getVaultLiquidity().utoi() + data.amountB0;

        require(
            (data.liquidity + data.lpsPnl) * ONE >= s.initialMarginRequired * poolInitialMarginMultiplier,
            'PI: pool insufficient liquidity'
        );
        require(
            margin + s.traderPnl >= s.traderInitialMarginRequired,
            'PI: insufficient margin'
        );

        lpsPnl = data.lpsPnl;
        cumulativePnlPerLiquidity = data.cumulativePnlPerLiquidity;
        protocolFeeAccrued += collect;

        tdInfos[data.tokenId].amountB0 = data.amountB0;
    }

    function liquidate(uint256 pTokenId, OracleSignature[] memory oracleSignatures) external _reentryLock_
    {
        require(
            address(privileger) == address(0) || privileger.isQualifiedLiquidator(msg.sender),
            'PI: unqualified liquidator'
        );

        _updateOracles(oracleSignatures);

        require(
            pToken.exists(pTokenId),
            'PI: nonexistent pTokenId'
        );

        Data memory data = _initializeDataWithAccount(msg.sender);
        data.vault = tdInfos[pTokenId].vault;
        data.amountB0 = tdInfos[pTokenId].amountB0;

        ISymbolManager.SettlementOnLiquidate memory s =
        symbolManager.settleSymbolsOnLiquidate(pTokenId, data.liquidity + data.lpsPnl);

        int256 undistributedPnl = s.funding - s.deltaTradersPnl + s.traderRealizedCost;

        data.amountB0 -= s.traderFunding;
        int256 margin = IVault(data.vault).getVaultLiquidity().utoi() + data.amountB0;

        require(
            s.traderMaintenanceMarginRequired > 0,
            'PI: no position'
        );
        require(
            margin + s.traderPnl < s.traderMaintenanceMarginRequired,
            'PI: cannot liquidate'
        );

        data.amountB0 -= s.traderRealizedCost;

        IVault v = IVault(data.vault);
        address[] memory assetsIn = v.getAssetsIn();

        for (uint256 i = 0; i < assetsIn.length; i++) {
            address asset = assetsIn[i];
            if (asset == tokenWETH) asset = address(0);
            uint256 balance = v.redeem(asset, type(uint256).max);
            if (asset == address(0)) {
                (uint256 resultB0, ) = swapper.swapExactETHForB0{value: balance}();
                data.amountB0 += resultB0.rescale(decimalsB0, 18).utoi(); // rescale resultB0 from decimalsB0 to 18
            } else if (asset == tokenB0) {
                data.amountB0 += balance.rescale(decimalsB0, 18).utoi(); // rescale balance from decimalsB0 to 18
            } else {
                (uint256 resultB0, ) = swapper.swapExactBXForB0(asset, balance);
                data.amountB0 += resultB0.rescale(decimalsB0, 18).utoi(); // rescale resultB0 from decimalsB0 to 18
            }
        }

        int256 reward;
        if (data.amountB0 <= minLiquidationReward) {
            reward = minLiquidationReward;
        } else {
            reward = (data.amountB0 - minLiquidationReward) * liquidationRewardCutRatio / ONE + minLiquidationReward;
            reward = reward.min(maxLiquidationReward);
        }
        reward = reward.itou().rescale(18, decimalsB0).rescale(decimalsB0, 18).utoi(); // make reward no remainder when convert to decimalsB0

        undistributedPnl += data.amountB0 - reward;
        data.lpsPnl += undistributedPnl;
        data.cumulativePnlPerLiquidity += undistributedPnl * ONE / data.liquidity;

        _transfer(tokenB0, msg.sender, reward.itou().rescale(18, decimalsB0)); // when transfer, use decimalsB0

        lpsPnl = data.lpsPnl;
        cumulativePnlPerLiquidity = data.cumulativePnlPerLiquidity;

        tdInfos[pTokenId].amountB0 = 0;
    }

    //================================================================================

    struct OracleSignature {
        bytes32 oracleSymbolId;
        uint256 timestamp;
        uint256 value;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    function _updateOracles(OracleSignature[] memory oracleSignatures) internal {
        for (uint256 i = 0; i < oracleSignatures.length; i++) {
            OracleSignature memory signature = oracleSignatures[i];
            oracleManager.updateValue(
                signature.oracleSymbolId,
                signature.timestamp,
                signature.value,
                signature.v,
                signature.r,
                signature.s
            );
        }
    }

    struct Data {
        int256 liquidity;
        int256 lpsPnl;
        int256 cumulativePnlPerLiquidity;

        address asset;
        address market;
        uint256 decimalsAsset;

        address account;
        uint256 tokenId;
        address vault;
        int256 amountB0;
        int256 lpLiquidity;
        int256 lpCumulativePnlPerLiquidity;
    }

//    function _initializeData() internal view returns (Data memory data) {
//        data.liquidity = liquidity;
//        data.lpsPnl = lpsPnl;
//        data.cumulativePnlPerLiquidity = cumulativePnlPerLiquidity;
//        data.account = msg.sender;
//    }

    function _initializeDataWithAccount(address account) internal view returns (Data memory data) {
        data.liquidity = liquidity;
        data.lpsPnl = lpsPnl;
        data.cumulativePnlPerLiquidity = cumulativePnlPerLiquidity;
        data.account = account;
    }

    function _initializeDataWithAccount(address account, address asset) internal view returns (Data memory data) {
        data = _initializeDataWithAccount(account);
        data.asset = asset;
        data.decimalsAsset = _getDecimalsAsset(asset); // get asset's decimals
        data.market = _getMarket(asset);
    }

//    function _initializeData(address asset) internal view returns (Data memory data) {
//        data = _initializeData();
//        data.asset = asset;
//        data.decimalsAsset = _getDecimalsAsset(asset); // get asset's decimals
//        data.market = _getMarket(asset);
//    }

    function _getDecimalsAsset(address asset) internal view returns (uint8) {
        if (asset == address(0)) {
            return 18;
        } else if (asset == tokenB0) {
            return decimalsB0;
        } else {
            return IERC20(asset).decimals();
        }
    }

    function _getMarket(address asset) internal view returns (address market) {
        if (asset == address(0)) {
            market = marketWETH;
        } else if (asset == tokenB0) {
            market = marketB0;
        } else {
            market = markets[asset];
            require(
                market != address(0),
                'PI: unsupported market'
            );
        }
    }

    function _getUnderlyingAsset(address market) internal view returns (address asset) {
        if (market == marketB0) {
            asset = tokenB0;
        } else if (market == marketWETH) {
            asset = address(0);
        } else {
            asset = IMarket(market).UNDERLYING_ASSET_ADDRESS();
        }
    }

    function _getLpInfo(Data memory data, bool createOnDemand) internal {
        data.tokenId = lToken.getTokenIdOf(data.account);
        if (data.tokenId == 0) {
            require(createOnDemand, 'PI: not LP');
            data.tokenId = lToken.mint(data.account);
            data.vault = _clone(vaultTemplate);
        } else {
            LpInfo storage info = lpInfos[data.tokenId];
            data.vault = info.vault;
            data.amountB0 = info.amountB0;
            data.lpLiquidity = info.liquidity;
            data.lpCumulativePnlPerLiquidity = info.cumulativePnlPerLiquidity;
        }
    }

    function _getTdInfo(Data memory data, bool createOnDemand) internal {
        data.tokenId = pToken.getTokenIdOf(data.account);
        if (data.tokenId == 0) {
            require(createOnDemand, 'PI: not trader');
            data.tokenId = pToken.mint(data.account);
            data.vault = _clone(vaultTemplate);
        } else {
            TdInfo storage info = tdInfos[data.tokenId];
            data.vault = info.vault;
            data.amountB0 = info.amountB0;
        }
    }

    function _clone(address source) internal returns (address target) {
        bytes20 sourceBytes = bytes20(source);
        assembly {
            let c := mload(0x40)
            mstore(c, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(c, 0x14), sourceBytes)
            mstore(add(c, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
            target := create(0, c, 0x37)
        }
    }

    function _settleLp(Data memory data) internal pure {
        int256 diff;
        unchecked { diff = data.cumulativePnlPerLiquidity - data.lpCumulativePnlPerLiquidity; }
        int256 pnl = diff * data.lpLiquidity / ONE;

        data.amountB0 += pnl;
        data.lpsPnl -= pnl;
        data.lpCumulativePnlPerLiquidity = data.cumulativePnlPerLiquidity;
    }

    // amount in asset's own decimals
    function _transfer(address asset, address to, uint256 amount) internal {
        if (asset == address(0)) {
            (bool success, ) = payable(to).call{value: amount}('');
            require(success, 'PI: send ETH fail');
        } else {
            IERC20(asset).safeTransfer(to, amount);
        }
    }

    // amount in asset's own decimals
    function _transferIn(Data memory data, uint256 amount) internal {
        IVault v = IVault(data.vault);

        if (data.asset == address(0)) { // ETH
            v.mint{value: amount}();
        }
        else if (data.asset == tokenB0) {
            uint256 reserve = amount * reserveRatioB0 / UONE;
            uint256 deposit = amount - reserve;

            IERC20(data.asset).safeTransferFrom(data.account, address(this), amount);
            IERC20(data.asset).safeTransfer(data.vault, deposit);

            v.mint(data.asset, deposit);
            data.amountB0 += reserve.rescale(data.decimalsAsset, 18).utoi(); // amountB0 is in decimals18
        }
        else {
            IERC20(data.asset).safeTransferFrom(data.account, data.vault, amount);
            v.mint(data.asset, amount);
        }
    }

    // amount/assetBalance are all in their own decimals
    function _transferOut(Data memory data, uint256 amount, uint256 assetBalance)
    internal returns (uint256 newVaultLiquidity)
    {
        IVault v = IVault(data.vault);

        if (assetBalance > 0) {
            // redeem asset, assetBalance is the exact redeemed amount
            assetBalance = v.redeem(data.asset, amount >= assetBalance ? type(uint256).max : amount);

            // if user has debt, pay it first
            if (data.amountB0 < 0) {
                (uint256 owe, uint256 excessive) = (-data.amountB0).itou().rescaleUp(18, decimalsB0); // amountB0 is in decimals18

                if (data.asset == address(0)) {
                    (uint256 resultB0, uint256 resultBX) = swapper.swapETHForExactB0{value: assetBalance}(owe);
                    data.amountB0 += resultB0.rescale(decimalsB0, 18).utoi(); // rescale resultB0 from decimalsB0 to 18
                    assetBalance -= resultBX;
                }
                else if (data.asset == tokenB0) {
                    if (assetBalance >= owe) {
                        data.amountB0 = excessive.utoi(); // excessive is already in decimals18
                        assetBalance -= owe;
                    } else {
                        data.amountB0 += assetBalance.rescale(decimalsB0, 18).utoi(); // rescale assetBalance to decimals18
                        assetBalance = 0;
                    }
                }
                else {
                    (uint256 resultB0, uint256 resultBX) = swapper.swapBXForExactB0(data.asset, owe, assetBalance);
                    data.amountB0 += resultB0.rescale(decimalsB0, 18).utoi(); // resultB0 to decimals18
                    assetBalance -= resultBX;
                }
            }

        }

        newVaultLiquidity = v.getVaultLiquidity();

        // user is removing all liquidity/margin completely
        // swap user's reserved amountB0 to his target token and transfer to him
        if (newVaultLiquidity == 0 && amount >= UMAX && data.amountB0 > 0) {
            (uint256 own, uint256 remainder) = data.amountB0.itou().rescaleDown(18, decimalsB0); // rescale amountB0 to decimalsB0
            uint256 resultBX;

            if (data.asset == address(0)) {
                (, resultBX) = swapper.swapExactB0ForETH(own);
            } else if (data.asset == tokenB0) {
                resultBX = own;
            } else {
                (, resultBX) = swapper.swapExactB0ForBX(data.asset, own);
            }

            assetBalance += resultBX;
            data.amountB0 = remainder.utoi(); // assign the remainder back to amountB0, which is not swappable
        }

        // user is removing tokenB0 and his intended amount is more than his vault's balance
        // use his reserved amountB0 to match user's intended amount if possible
        if (data.asset == tokenB0 && data.amountB0 > 0 && amount > assetBalance) {
            uint256 own = data.amountB0.itou().rescale(18, decimalsB0); // rescale amountB0 to decimalsB0
            uint256 resultBX = own.min(amount - assetBalance);

            assetBalance += resultBX;
            data.amountB0 -= resultBX.rescale(decimalsB0, 18).utoi();
        }

        if (assetBalance > 0) {
            _transfer(data.asset, data.account, assetBalance);
        }
    }

}

