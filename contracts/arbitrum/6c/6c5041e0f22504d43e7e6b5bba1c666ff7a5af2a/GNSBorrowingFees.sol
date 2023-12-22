// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Initializable} from "./Initializable.sol";

import "./IGNSBorrowingFees.sol";
import "./IGNSTradingStorage.sol";
import "./IGNSPairInfos.sol";

import "./ChainUtils.sol";
import "./PriceImpactUtils.sol";

/**
 * @custom:version 6.4.2
 * @custom:oz-upgrades-unsafe-allow external-library-linking
 */
contract GNSBorrowingFees is Initializable, IGNSBorrowingFees {
    // Constants
    uint256 constant P_1 = 1e10;
    uint256 constant P_2 = 1e40;

    // Addresses
    IGNSTradingStorage public storageT;
    IGNSPairInfos public pairInfos;

    // State
    mapping(uint16 => Group) public groups;
    mapping(uint256 => Pair) public pairs;
    mapping(address => mapping(uint256 => mapping(uint256 => InitialAccFees))) public initialAccFees;
    mapping(uint256 => PairOi) public pairOis;
    mapping(uint256 => uint48) public groupFeeExponents;

    // v6.4.2 Storage & state
    PriceImpactUtils.OiWindowsStorage private oiWindowsStorage;

    function initialize(IGNSTradingStorage _storageT, IGNSPairInfos _pairInfos) external initializer {
        require(address(_storageT) != address(0) && address(_pairInfos) != address(0), "WRONG_PARAMS");

        storageT = _storageT;
        pairInfos = _pairInfos;
    }

    function initializeV2(uint48 _windowsDuration) external reinitializer(2) {
        PriceImpactUtils.initializeOiWindowsSettings(_windowsDuration);
    }

    // Modifiers
    modifier onlyManager() {
        require(msg.sender == pairInfos.manager(), "MANAGER_ONLY");
        _;
    }

    modifier onlyCallbacks() {
        require(msg.sender == storageT.callbacks(), "CALLBACKS_ONLY");
        _;
    }

    // Manage pair params
    function setPairParams(uint256 pairIndex, PairParams calldata value) external onlyManager {
        _setPairParams(pairIndex, value);
    }

    function setPairParamsArray(uint256[] calldata indices, PairParams[] calldata values) external onlyManager {
        uint256 len = indices.length;
        require(len == values.length, "WRONG_LENGTH");

        for (uint256 i; i < len; ) {
            _setPairParams(indices[i], values[i]);
            unchecked {
                ++i;
            }
        }
    }

    function _setPairParams(uint256 pairIndex, PairParams calldata value) private {
        require(value.feeExponent >= 1 && value.feeExponent <= 3, "WRONG_EXPONENT");

        Pair storage p = pairs[pairIndex];

        uint16 prevGroupIndex = getPairGroupIndex(pairIndex);
        uint256 currentBlock = ChainUtils.getBlockNumber();

        _setPairPendingAccFees(pairIndex, currentBlock);

        if (value.groupIndex != prevGroupIndex) {
            _setGroupPendingAccFees(prevGroupIndex, currentBlock);
            _setGroupPendingAccFees(value.groupIndex, currentBlock);

            (uint256 oiLong, uint256 oiShort) = getPairOpenInterestDai(pairIndex);

            // Only remove OI from old group if old group is not 0
            _setGroupOi(prevGroupIndex, true, false, oiLong);
            _setGroupOi(prevGroupIndex, false, false, oiShort);

            // Add OI to new group if it's not group 0 (even if old group is 0)
            // So when we assign a pair to a group, it takes into account its OI
            // And group 0 OI will always be 0 but it doesn't matter since it's not used
            _setGroupOi(value.groupIndex, true, true, oiLong);
            _setGroupOi(value.groupIndex, false, true, oiShort);

            Group memory newGroup = groups[value.groupIndex];
            Group memory prevGroup = groups[prevGroupIndex];

            p.groups.push(
                PairGroup(
                    value.groupIndex,
                    ChainUtils.getUint48BlockNumber(currentBlock),
                    newGroup.accFeeLong,
                    newGroup.accFeeShort,
                    prevGroup.accFeeLong,
                    prevGroup.accFeeShort,
                    p.accFeeLong,
                    p.accFeeShort,
                    0 // placeholder
                )
            );

            emit PairGroupUpdated(pairIndex, prevGroupIndex, value.groupIndex);
        }

        p.feePerBlock = value.feePerBlock;
        p.feeExponent = value.feeExponent;
        pairOis[pairIndex].max = value.maxOi;

        emit PairParamsUpdated(pairIndex, value.groupIndex, value.feePerBlock, value.feeExponent, value.maxOi);
    }

    // Manage group params
    function setGroupParams(uint16 groupIndex, GroupParams calldata value) external onlyManager {
        _setGroupParams(groupIndex, value);
    }

    function setGroupParamsArray(uint16[] calldata indices, GroupParams[] calldata values) external onlyManager {
        uint256 len = indices.length;
        require(len == values.length, "WRONG_LENGTH");

        for (uint256 i; i < len; ) {
            _setGroupParams(indices[i], values[i]);
            unchecked {
                ++i;
            }
        }
    }

    function _setGroupParams(uint16 groupIndex, GroupParams calldata value) private {
        require(groupIndex > 0, "GROUP_0");
        require(value.feeExponent >= 1 && value.feeExponent <= 3, "WRONG_EXPONENT");

        _setGroupPendingAccFees(groupIndex, ChainUtils.getBlockNumber());

        Group storage g = groups[groupIndex];
        g.feePerBlock = value.feePerBlock;
        g.maxOi = uint80(value.maxOi);
        groupFeeExponents[groupIndex] = value.feeExponent;

        emit GroupUpdated(groupIndex, value.feePerBlock, value.maxOi, value.feeExponent);
    }

    // Group OI setter
    function _setGroupOi(
        uint16 groupIndex,
        bool long,
        bool increase,
        uint256 amount // 1e18
    ) private {
        Group storage group = groups[groupIndex];
        uint112 amountFinal;

        if (groupIndex > 0) {
            amount = (amount * P_1) / 1e18; // 1e10
            require(amount <= type(uint112).max, "OVERFLOW");

            amountFinal = uint112(amount);

            if (long) {
                group.oiLong = increase
                    ? group.oiLong + amountFinal
                    : group.oiLong - (group.oiLong > amountFinal ? amountFinal : group.oiLong);
            } else {
                group.oiShort = increase
                    ? group.oiShort + amountFinal
                    : group.oiShort - (group.oiShort > amountFinal ? amountFinal : group.oiShort);
            }
        }

        emit GroupOiUpdated(groupIndex, long, increase, amountFinal, group.oiLong, group.oiShort);
    }

    // Acc fees getters for pairs and groups
    function getPendingAccFees(
        PendingAccFeesInput memory input
    ) public pure returns (uint64 newAccFeeLong, uint64 newAccFeeShort, uint64 delta) {
        require(input.currentBlock >= input.accLastUpdatedBlock, "BLOCK_ORDER");

        bool moreShorts = input.oiLong < input.oiShort;
        uint256 netOi = moreShorts ? input.oiShort - input.oiLong : input.oiLong - input.oiShort;

        uint256 _delta = input.maxOi > 0 && input.feeExponent > 0
            ? ((input.currentBlock - input.accLastUpdatedBlock) *
                input.feePerBlock *
                ((netOi * 1e10) / input.maxOi) ** input.feeExponent) / (1e18 ** input.feeExponent)
            : 0; // 1e10 (%)

        require(_delta <= type(uint64).max, "OVERFLOW");
        delta = uint64(_delta);

        newAccFeeLong = moreShorts ? input.accFeeLong : input.accFeeLong + delta;
        newAccFeeShort = moreShorts ? input.accFeeShort + delta : input.accFeeShort;
    }

    function getPairGroupAccFeesDeltas(
        uint256 i,
        PairGroup[] memory pairGroups,
        InitialAccFees memory initialFees,
        uint256 pairIndex,
        bool long,
        uint256 currentBlock
    ) public view returns (uint64 deltaGroup, uint64 deltaPair, bool beforeTradeOpen) {
        PairGroup memory group = pairGroups[i];

        beforeTradeOpen = group.block < initialFees.block;

        if (i == pairGroups.length - 1) {
            // Last active group
            deltaGroup = getGroupPendingAccFee(group.groupIndex, currentBlock, long);
            deltaPair = getPairPendingAccFee(pairIndex, currentBlock, long);
        } else {
            // Previous groups
            PairGroup memory nextGroup = pairGroups[i + 1];

            // If it's not the first group to be before the trade was opened then fee is 0
            if (beforeTradeOpen && nextGroup.block <= initialFees.block) {
                return (0, 0, beforeTradeOpen);
            }

            deltaGroup = long ? nextGroup.prevGroupAccFeeLong : nextGroup.prevGroupAccFeeShort;
            deltaPair = long ? nextGroup.pairAccFeeLong : nextGroup.pairAccFeeShort;
        }

        if (beforeTradeOpen) {
            deltaGroup -= initialFees.accGroupFee;
            deltaPair -= initialFees.accPairFee;
        } else {
            deltaGroup -= (long ? group.initialAccFeeLong : group.initialAccFeeShort);
            deltaPair -= (long ? group.pairAccFeeLong : group.pairAccFeeShort);
        }
    }

    // Pair acc fees helpers
    function getPairPendingAccFees(
        uint256 pairIndex,
        uint256 currentBlock
    ) public view returns (uint64 accFeeLong, uint64 accFeeShort, uint64 pairAccFeeDelta) {
        Pair memory pair = pairs[pairIndex];

        (uint256 pairOiLong, uint256 pairOiShort) = getPairOpenInterestDai(pairIndex);

        (accFeeLong, accFeeShort, pairAccFeeDelta) = getPendingAccFees(
            PendingAccFeesInput(
                pair.accFeeLong,
                pair.accFeeShort,
                pairOiLong,
                pairOiShort,
                pair.feePerBlock,
                currentBlock,
                pair.accLastUpdatedBlock,
                pairOis[pairIndex].max,
                pair.feeExponent
            )
        );
    }

    function getPairPendingAccFee(
        uint256 pairIndex,
        uint256 currentBlock,
        bool long
    ) public view returns (uint64 accFee) {
        (uint64 accFeeLong, uint64 accFeeShort, ) = getPairPendingAccFees(pairIndex, currentBlock);
        return long ? accFeeLong : accFeeShort;
    }

    function _setPairPendingAccFees(
        uint256 pairIndex,
        uint256 currentBlock
    ) private returns (uint64 accFeeLong, uint64 accFeeShort) {
        (accFeeLong, accFeeShort, ) = getPairPendingAccFees(pairIndex, currentBlock);

        Pair storage pair = pairs[pairIndex];

        (pair.accFeeLong, pair.accFeeShort) = (accFeeLong, accFeeShort);
        pair.accLastUpdatedBlock = ChainUtils.getUint48BlockNumber(currentBlock);

        emit PairAccFeesUpdated(pairIndex, currentBlock, pair.accFeeLong, pair.accFeeShort);
    }

    // Group acc fees helpers
    function getGroupPendingAccFees(
        uint16 groupIndex,
        uint256 currentBlock
    ) public view returns (uint64 accFeeLong, uint64 accFeeShort, uint64 groupAccFeeDelta) {
        Group memory group = groups[groupIndex];

        (accFeeLong, accFeeShort, groupAccFeeDelta) = getPendingAccFees(
            PendingAccFeesInput(
                group.accFeeLong,
                group.accFeeShort,
                (uint256(group.oiLong) * 1e18) / P_1,
                (uint256(group.oiShort) * 1e18) / P_1,
                group.feePerBlock,
                currentBlock,
                group.accLastUpdatedBlock,
                uint72(group.maxOi),
                groupFeeExponents[groupIndex]
            )
        );
    }

    function getGroupPendingAccFee(
        uint16 groupIndex,
        uint256 currentBlock,
        bool long
    ) public view returns (uint64 accFee) {
        (uint64 accFeeLong, uint64 accFeeShort, ) = getGroupPendingAccFees(groupIndex, currentBlock);
        return long ? accFeeLong : accFeeShort;
    }

    function _setGroupPendingAccFees(
        uint16 groupIndex,
        uint256 currentBlock
    ) private returns (uint64 accFeeLong, uint64 accFeeShort) {
        (accFeeLong, accFeeShort, ) = getGroupPendingAccFees(groupIndex, currentBlock);

        Group storage group = groups[groupIndex];

        (group.accFeeLong, group.accFeeShort) = (accFeeLong, accFeeShort);
        group.accLastUpdatedBlock = ChainUtils.getUint48BlockNumber(currentBlock);

        emit GroupAccFeesUpdated(groupIndex, currentBlock, group.accFeeLong, group.accFeeShort);
    }

    // Interaction with callbacks
    function handleTradeAction(
        address trader,
        uint256 pairIndex,
        uint256 index,
        uint256 positionSizeDai, // 1e18 (collateral * leverage)
        bool open,
        bool long
    ) external override onlyCallbacks {
        uint16 groupIndex = getPairGroupIndex(pairIndex);
        uint256 currentBlock = ChainUtils.getBlockNumber();

        (uint64 pairAccFeeLong, uint64 pairAccFeeShort) = _setPairPendingAccFees(pairIndex, currentBlock);
        (uint64 groupAccFeeLong, uint64 groupAccFeeShort) = _setGroupPendingAccFees(groupIndex, currentBlock);

        _setGroupOi(groupIndex, long, open, positionSizeDai);

        if (open) {
            InitialAccFees memory initialFees = InitialAccFees(
                long ? pairAccFeeLong : pairAccFeeShort,
                long ? groupAccFeeLong : groupAccFeeShort,
                ChainUtils.getUint48BlockNumber(currentBlock),
                0 // placeholder
            );

            initialAccFees[trader][pairIndex][index] = initialFees;

            emit TradeInitialAccFeesStored(trader, pairIndex, index, initialFees.accPairFee, initialFees.accGroupFee);
        }

        emit TradeActionHandled(trader, pairIndex, index, open, long, positionSizeDai);
    }

    // Important trade getters
    function getTradeBorrowingFee(BorrowingFeeInput memory input) public view returns (uint256 fee) {
        InitialAccFees memory initialFees = initialAccFees[input.trader][input.pairIndex][input.index];
        PairGroup[] memory pairGroups = pairs[input.pairIndex].groups;

        uint256 currentBlock = ChainUtils.getBlockNumber();

        PairGroup memory firstPairGroup;
        if (pairGroups.length > 0) {
            firstPairGroup = pairGroups[0];
        }

        // If pair has had no group after trade was opened, initialize with pair borrowing fee
        if (pairGroups.length == 0 || firstPairGroup.block > initialFees.block) {
            fee = ((
                pairGroups.length == 0
                    ? getPairPendingAccFee(input.pairIndex, currentBlock, input.long)
                    : (input.long ? firstPairGroup.pairAccFeeLong : firstPairGroup.pairAccFeeShort)
            ) - initialFees.accPairFee);
        }

        // Sum of max(pair fee, group fee) for all groups the pair was in while trade was open
        for (uint256 i = pairGroups.length; i > 0; ) {
            (uint64 deltaGroup, uint64 deltaPair, bool beforeTradeOpen) = getPairGroupAccFeesDeltas(
                i - 1,
                pairGroups,
                initialFees,
                input.pairIndex,
                input.long,
                currentBlock
            );

            fee += (deltaGroup > deltaPair ? deltaGroup : deltaPair);

            // Exit loop at first group before trade was open
            if (beforeTradeOpen) break;
            unchecked {
                --i;
            }
        }

        fee = (input.collateral * input.leverage * fee) / P_1 / 100; // 1e18 (DAI)
    }

    function getTradeLiquidationPrice(LiqPriceInput calldata input) external view returns (uint256) {
        return
            pairInfos.getTradeLiquidationPricePure(
                input.openPrice,
                input.long,
                input.collateral,
                input.leverage,
                pairInfos.getTradeRolloverFee(input.trader, input.pairIndex, input.index, input.collateral) +
                    getTradeBorrowingFee(
                        BorrowingFeeInput(
                            input.trader,
                            input.pairIndex,
                            input.index,
                            input.long,
                            input.collateral,
                            input.leverage
                        )
                    ),
                pairInfos.getTradeFundingFee(
                    input.trader,
                    input.pairIndex,
                    input.index,
                    input.long,
                    input.collateral,
                    input.leverage
                )
            );
    }

    // Public getters
    function getPairOpenInterestDai(uint256 pairIndex) public view returns (uint256, uint256) {
        return (storageT.openInterestDai(pairIndex, 0), storageT.openInterestDai(pairIndex, 1));
    }

    function getPairGroupIndex(uint256 pairIndex) public view returns (uint16 groupIndex) {
        PairGroup[] memory pairGroups = pairs[pairIndex].groups;
        return pairGroups.length == 0 ? 0 : pairGroups[pairGroups.length - 1].groupIndex;
    }

    // External getters
    function withinMaxGroupOi(
        uint256 pairIndex,
        bool long,
        uint256 positionSizeDai // 1e18
    ) external view returns (bool) {
        Group memory g = groups[getPairGroupIndex(pairIndex)];
        return (g.maxOi == 0) || ((long ? g.oiLong : g.oiShort) + (positionSizeDai * P_1) / 1e18 <= g.maxOi);
    }

    function getGroup(uint16 groupIndex) external view returns (Group memory, uint48) {
        return (groups[groupIndex], groupFeeExponents[groupIndex]);
    }

    function getPair(uint256 pairIndex) external view returns (Pair memory, PairOi memory) {
        return (pairs[pairIndex], pairOis[pairIndex]);
    }

    function getAllPairs() external view returns (Pair[] memory, PairOi[] memory) {
        uint256 len = storageT.priceAggregator().pairsStorage().pairsCount();
        Pair[] memory p = new Pair[](len);
        PairOi[] memory pairOi = new PairOi[](len);

        for (uint256 i; i < len; ) {
            p[i] = pairs[i];
            pairOi[i] = pairOis[i];
            unchecked {
                ++i;
            }
        }

        return (p, pairOi);
    }

    function getGroups(uint16[] calldata indices) external view returns (Group[] memory, uint48[] memory) {
        Group[] memory g = new Group[](indices.length);
        uint48[] memory e = new uint48[](indices.length);
        uint256 len = indices.length;

        for (uint256 i; i < len; ) {
            g[i] = groups[indices[i]];
            e[i] = groupFeeExponents[indices[i]];
            unchecked {
                ++i;
            }
        }

        return (g, e);
    }

    function getTradeInitialAccFees(
        address trader,
        uint256 pairIndex,
        uint256 index
    ) external view returns (InitialAccFees memory borrowingFees, IGNSPairInfos.TradeInitialAccFees memory otherFees) {
        borrowingFees = initialAccFees[trader][pairIndex][index];
        otherFees = pairInfos.tradeInitialAccFees(trader, pairIndex, index);
    }

    function getPairMaxOi(uint256 pairIndex) external view returns (uint256) {
        return pairOis[pairIndex].max;
    }

    /**
     * v6.4.2
     */

    // Setters
    function setPriceImpactWindowsCount(uint48 _newWindowsCount) external onlyManager {
        PriceImpactUtils.setPriceImpactWindowsCount(_newWindowsCount);
    }

    function setPriceImpactWindowsDuration(uint48 _newWindowsDuration) external onlyManager {
        PriceImpactUtils.setPriceImpactWindowsDuration(
            _newWindowsDuration,
            storageT.priceAggregator().pairsStorage().pairsCount()
        );
    }

    // Helpers (permissioned)
    function addPriceImpactOpenInterest(uint256 _openInterest, uint256 _pairIndex, bool _long) external onlyCallbacks {
        PriceImpactUtils.addPriceImpactOpenInterest(uint128(_openInterest), _pairIndex, _long);
    }

    function removePriceImpactOpenInterest(
        uint256 _openInterest,
        uint256 _pairIndex,
        bool _long,
        uint48 _addTs
    ) external onlyCallbacks {
        PriceImpactUtils.removePriceImpactOpenInterest(uint128(_openInterest), _pairIndex, _long, _addTs);
    }

    // Getters
    function getPriceImpactOi(uint256 _pairIndex, bool _long) public view returns (uint256 activeOi) {
        return PriceImpactUtils.getPriceImpactOi(_pairIndex, _long, storageT);
    }

    function getTradePriceImpact(
        uint256 _openPrice, // PRECISION
        uint256 _pairIndex,
        bool _long,
        uint256 _tradeOpenInterest // 1e18 (DAI)
    )
        external
        view
        returns (
            uint256 priceImpactP, // PRECISION (%)
            uint256 priceAfterImpact // PRECISION
        )
    {
        IGNSPairInfos.PairParams memory pParams = pairInfos.pairParams(_pairIndex);
        uint256 depth = _long ? pParams.onePercentDepthAbove : pParams.onePercentDepthBelow;

        (priceImpactP, priceAfterImpact) = PriceImpactUtils.getTradePriceImpact(
            _openPrice,
            _long,
            depth > 0 ? getPriceImpactOi(_pairIndex, _long) : 0, // saves gas if depth is 0
            _tradeOpenInterest,
            depth
        );
    }

    function getOiWindowsSettings() external view returns (PriceImpactUtils.OiWindowsSettings memory) {
        return oiWindowsStorage.settings;
    }

    function getOiWindow(
        uint48 _windowsDuration,
        uint256 _pairIndex,
        uint256 _windowId
    ) external view returns (PriceImpactUtils.PairOi memory) {
        return
            oiWindowsStorage.windows[
                _windowsDuration > 0 ? _windowsDuration : oiWindowsStorage.settings.windowsDuration
            ][_pairIndex][_windowId];
    }

    function getOiWindows(
        uint48 _windowsDuration,
        uint256 _pairIndex,
        uint256[] calldata _windowIds
    ) external view returns (PriceImpactUtils.PairOi[] memory) {
        PriceImpactUtils.PairOi[] memory _pairOis = new PriceImpactUtils.PairOi[](_windowIds.length);
        _windowsDuration = _windowsDuration > 0 ? _windowsDuration : oiWindowsStorage.settings.windowsDuration;

        for (uint256 i; i < _windowIds.length; ) {
            _pairOis[i] = oiWindowsStorage.windows[_windowsDuration][_pairIndex][_windowIds[i]];

            unchecked {
                ++i;
            }
        }

        return _pairOis;
    }
}

