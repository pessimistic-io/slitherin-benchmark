// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IBorrowingFees.sol";
import "./ITradingStorage.sol";
import "./IPairInfos.sol";
import "./ChainUtils.sol";


contract BorrowingFees is IBorrowingFees {
   
    uint256 constant P_1 = 1e10;
    uint256 constant P_2 = 1e40;

    ITradingStorage public storageT;
    IPairInfos public pairInfos;

    mapping(uint16 => Group) public groups;
    mapping(uint256 => Pair) public pairs;
    mapping(address => mapping(uint256 => mapping(uint256 => InitialAccFees))) public initialAccFees;

    error BorrowingFeesWrongParameters();
    error BorrowingFeesInvalidManagerAddress(address account);
    error BorrowingFeesInvalidCallbacksContract(address account);
    error BorrowingFeesOverflow();
    error BorrowingFeesBlockOrder();

    modifier onlyManager(){
        if (msg.sender != pairInfos.manager()) {
            revert BorrowingFeesInvalidManagerAddress(msg.sender);
        }
        _;
    }
    modifier onlyCallbacks(){
        if (msg.sender != storageT.callbacks()) {
            revert BorrowingFeesInvalidCallbacksContract(msg.sender);
        }
        _;
    }

    constructor(ITradingStorage _storageT, IPairInfos _pairInfos) {
        if (address(_storageT) == address(0) || address(_pairInfos) == address(0)) revert BorrowingFeesWrongParameters();

        storageT = _storageT;
        pairInfos = _pairInfos;
    }

    function setPairParams(uint256 pairIndex, PairParams calldata value) external onlyManager {
        _setPairParams(pairIndex, value);
    }

    function setPairParamsArray(uint256[] calldata indices, PairParams[] calldata values) external onlyManager {
        uint256 len = indices.length;
        if (len != values.length) revert BorrowingFeesWrongParameters();

        for (uint256 i; i < len; ) {
            _setPairParams(indices[i], values[i]);
            unchecked {
                ++i;
            }
        }
    }

    function setGroupParams(uint16 groupIndex, GroupParams calldata value) external onlyManager {
        _setGroupParams(groupIndex, value);
    }

    function setGroupParamsArray(uint16[] calldata indices, GroupParams[] calldata values) external onlyManager {
        uint256 len = indices.length;
        if (len != values.length) revert BorrowingFeesWrongParameters();

        for (uint256 i; i < len; ) {
            _setGroupParams(indices[i], values[i]);
            unchecked {
                ++i;
            }
        }
    }

    function handleTradeAction(
        address trader,
        uint256 pairIndex,
        uint256 index,
        uint256 positionSizeStable,
        bool open,
        bool long
    ) external override onlyCallbacks {
        uint16 groupIndex = getPairGroupIndex(pairIndex);
        uint256 currentBlock = ChainUtils.getBlockNumber();

        (uint64 pairAccFeeLong, uint64 pairAccFeeShort) = _setPairPendingAccFees(pairIndex, currentBlock);
        (uint64 groupAccFeeLong, uint64 groupAccFeeShort) = _setGroupPendingAccFees(groupIndex, currentBlock);

        _setGroupOi(groupIndex, long, open, positionSizeStable);

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

        emit TradeActionHandled(trader, pairIndex, index, open, long, positionSizeStable);
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

    function withinMaxGroupOi(
        uint256 pairIndex,
        bool long,
        uint256 positionSizeStable 
    ) external view returns (bool) {
        Group memory g = groups[getPairGroupIndex(pairIndex)];
        return (g.maxOi == 0) || ((long ? g.oiLong : g.oiShort) + (positionSizeStable * P_1) / 1e18 <= g.maxOi);
    }

    function getGroup(uint16 groupIndex) external view returns (Group memory) {
        return groups[groupIndex];
    }

    function getPair(uint256 pairIndex) external view returns (Pair memory) {
        return pairs[pairIndex];
    }

    function getAllPairs() external view returns (Pair[] memory) {
        uint256 len = storageT.priceAggregator().pairsStorage().pairsCount();
        Pair[] memory p = new Pair[](len);

        for (uint256 i; i < len; ) {
            p[i] = pairs[i];
            unchecked {
                ++i;
            }
        }

        return p;
    }

    function getGroups(uint16[] calldata indices) external view returns (Group[] memory) {
        Group[] memory g = new Group[](indices.length);
        uint256 len = indices.length;

        for (uint256 i; i < len; ) {
            g[i] = groups[indices[i]];
            unchecked {
                ++i;
            }
        }

        return g;
    }

    function getTradeInitialAccFees(
        address trader,
        uint256 pairIndex,
        uint256 index
    )
        external
        view
        returns (InitialAccFees memory borrowingFees, IPairInfos.TradeInitialAccFees memory otherFees)
    {
        borrowingFees = initialAccFees[trader][pairIndex][index];
        otherFees = pairInfos.tradeInitialAccFees(trader, pairIndex, index);
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

    function getPairPendingAccFees(
        uint256 pairIndex,
        uint256 currentBlock
    ) public view returns (uint64 accFeeLong, uint64 accFeeShort, int256 pairAccFeeDelta) {
        uint256 workPoolMarketCap = getPairWeightedWorkPoolMarketCapSinceLastUpdate(pairIndex, currentBlock);
        Pair memory pair = pairs[pairIndex];

        (uint256 pairOiLong, uint256 pairOiShort) = getPairOpenInterestStable(pairIndex);

        (accFeeLong, accFeeShort, pairAccFeeDelta) = getPendingAccFees(
            pair.accFeeLong,
            pair.accFeeShort,
            pairOiLong,
            pairOiShort,
            pair.feePerBlock,
            currentBlock,
            pair.accLastUpdatedBlock,
            workPoolMarketCap
        );
    }

    function getPairPendingAccFee(uint256 pairIndex, uint256 currentBlock, bool long) public view returns (uint64 accFee) {
        (uint64 accFeeLong, uint64 accFeeShort, ) = getPairPendingAccFees(pairIndex, currentBlock);
        return long ? accFeeLong : accFeeShort;
    }

    function getGroupPendingAccFees(
        uint16 groupIndex,
        uint256 currentBlock
    ) public view returns (uint64 accFeeLong, uint64 accFeeShort, int256 groupAccFeeDelta) {
        uint workPoolMarketCap = getGroupWeightedWorkPoolMarketCapSinceLastUpdate(groupIndex, currentBlock);
        Group memory group = groups[groupIndex];

        (accFeeLong, accFeeShort, groupAccFeeDelta) = getPendingAccFees(
            group.accFeeLong,
            group.accFeeShort,
            (uint256(group.oiLong) * 1e18) / P_1,
            (uint256(group.oiShort) * 1e18) / P_1,
            group.feePerBlock,
            currentBlock,
            group.accLastUpdatedBlock,
            workPoolMarketCap
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

        fee = (input.collateral * input.leverage * fee) / P_1 / 100;
    }

    function getPairOpenInterestStable(uint256 pairIndex) public view returns (uint256, uint256) {
        return (storageT.openInterestStable(pairIndex, 0), storageT.openInterestStable(pairIndex, 1));
    }

    function getPairGroupIndex(uint256 pairIndex) public view returns (uint16 groupIndex) {
        PairGroup[] memory pairGroups = pairs[pairIndex].groups;
        return pairGroups.length == 0 ? 0 : pairGroups[pairGroups.length - 1].groupIndex;
    }

    function getPendingAccBlockWeightedMarketCap(uint256 currentBlock) public view returns (uint256) {
        return IWorkPool(storageT.workPool()).getPendingAccBlockWeightedMarketCap(currentBlock);
    }

    function getGroupWeightedWorkPoolMarketCapSinceLastUpdate(
        uint16 groupIndex,
        uint256 currentBlock
    ) public view returns (uint256) {
        Group memory g = groups[groupIndex];
        return
            getWeightedWorkPoolMarketCap(
                getPendingAccBlockWeightedMarketCap(currentBlock),
                g.lastAccBlockWeightedMarketCap,
                currentBlock - g.accLastUpdatedBlock
            );
    }

    function getPairWeightedWorkPoolMarketCapSinceLastUpdate(
        uint256 pairIndex,
        uint256 currentBlock
    ) public view returns (uint256) {
        Pair memory p = pairs[pairIndex];
        return
            getWeightedWorkPoolMarketCap(
                getPendingAccBlockWeightedMarketCap(currentBlock),
                p.lastAccBlockWeightedMarketCap,
                currentBlock - p.accLastUpdatedBlock
            );
    }

    function getPendingAccFees(
        uint64 accFeeLong, 
        uint64 accFeeShort, 
        uint256 oiLong, 
        uint256 oiShort, 
        uint32 feePerBlock, 
        uint256 currentBlock,
        uint256 accLastUpdatedBlock,
        uint256 workPoolMarketCap 
    ) public pure returns (uint64 newAccFeeLong, uint64 newAccFeeShort, int256 delta) {
        if (currentBlock < accLastUpdatedBlock) revert BorrowingFeesBlockOrder();

        delta =
            ((int256(oiLong) - int256(oiShort)) * int256(uint256(feePerBlock)) * int256(currentBlock - accLastUpdatedBlock)) /
            int256(workPoolMarketCap); 

        uint256 deltaUint;

        if (delta < 0) {
            deltaUint = uint256(delta * (-1));
            newAccFeeLong = accFeeLong;
            newAccFeeShort = accFeeShort + uint64(deltaUint);
        } else {
            deltaUint = uint256(delta);
            newAccFeeLong = accFeeLong + uint64(deltaUint);
            newAccFeeShort = accFeeShort;
        }

        if (deltaUint > type(uint64).max) revert BorrowingFeesOverflow();
    }

    function getWeightedWorkPoolMarketCap(
        uint256 accBlockWeightedMarketCap,
        uint256 lastAccBlockWeightedMarketCap,
        uint256 blockDelta
    ) public pure returns (uint256) {
        // return 1 in case blockDelta is 0 since acc borrowing fees delta will be 0 anyway, and 0 / 1 = 0
        return blockDelta > 0 ? (blockDelta * P_2) / (accBlockWeightedMarketCap - lastAccBlockWeightedMarketCap) : 1; 
    }

    function _setPairParams(uint256 pairIndex, PairParams calldata value) private {
        Pair storage p = pairs[pairIndex];

        uint16 prevGroupIndex = getPairGroupIndex(pairIndex);
        uint256 currentBlock = ChainUtils.getBlockNumber();

        _setPairPendingAccFees(pairIndex, currentBlock);

        if (value.groupIndex != prevGroupIndex) {
            _setGroupPendingAccFees(prevGroupIndex, currentBlock);
            _setGroupPendingAccFees(value.groupIndex, currentBlock);

            (uint256 oiLong, uint256 oiShort) = getPairOpenInterestStable(pairIndex);

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

        emit PairParamsUpdated(pairIndex, value.groupIndex, value.feePerBlock);
    }

    function _setGroupParams(uint16 groupIndex, GroupParams calldata value) private {
        if (groupIndex == 0) revert BorrowingFeesWrongParameters();

        _setGroupPendingAccFees(groupIndex, ChainUtils.getBlockNumber());
        groups[groupIndex].feePerBlock = value.feePerBlock;
        groups[groupIndex].maxOi = value.maxOi;

        emit GroupUpdated(groupIndex, value.feePerBlock, value.maxOi);
    }

    function _setGroupOi(
        uint16 groupIndex,
        bool long,
        bool increase,
        uint256 amount 
    ) private {
        Group storage group = groups[groupIndex];
        uint112 amountFinal;

        if (groupIndex > 0) {
            amount = (amount * P_1) / 1e18; 
            if (amount > type(uint112).max) revert BorrowingFeesOverflow();

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

    function _setPairPendingAccFees(
        uint256 pairIndex,
        uint256 currentBlock
    ) private returns (uint64 accFeeLong, uint64 accFeeShort) {
        int256 delta;
        (accFeeLong, accFeeShort, delta) = getPairPendingAccFees(pairIndex, currentBlock);

        Pair storage pair = pairs[pairIndex];

        (pair.accFeeLong, pair.accFeeShort) = (accFeeLong, accFeeShort);
        pair.accLastUpdatedBlock = ChainUtils.getUint48BlockNumber(currentBlock);
        pair.lastAccBlockWeightedMarketCap = getPendingAccBlockWeightedMarketCap(currentBlock);

        emit PairAccFeesUpdated(
            pairIndex,
            currentBlock,
            pair.accFeeLong,
            pair.accFeeShort,
            pair.lastAccBlockWeightedMarketCap
        );
    }

    function _setGroupPendingAccFees(
        uint16 groupIndex,
        uint256 currentBlock
    ) private returns (uint64 accFeeLong, uint64 accFeeShort) {
        int256 delta;
        (accFeeLong, accFeeShort, delta) = getGroupPendingAccFees(groupIndex, currentBlock);

        Group storage group = groups[groupIndex];

        (group.accFeeLong, group.accFeeShort) = (accFeeLong, accFeeShort);
        group.accLastUpdatedBlock = ChainUtils.getUint48BlockNumber(currentBlock);
        group.lastAccBlockWeightedMarketCap = getPendingAccBlockWeightedMarketCap(currentBlock);

        emit GroupAccFeesUpdated(
            groupIndex,
            currentBlock,
            group.accFeeLong,
            group.accFeeShort,
            group.lastAccBlockWeightedMarketCap
        );
    }
}

