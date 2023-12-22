// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {LibDiamond} from "./LibDiamond.sol";
import {IAddressProvider} from "./IAddressProvider.sol";
import {Amm, AppStorage, CurveSettings, LibMagpieRouter} from "./LibMagpieRouter.sol";
import {LibAsset} from "./LibAsset.sol";
import {LibBytes} from "./LibBytes.sol";
import {LibUint256Array} from "./LibUint256Array.sol";
import {Hop, HopParams} from "./LibHop.sol";

struct SwapArgs {
    uint256 amountOut;
    uint256 amountOutMin;
    uint256 deadline;
    uint256[] amountIns;
    bytes32[] hops;
    bytes addresses;
    bytes poolData;
}

struct SwapState {
    uint16 hopAmmId;
    uint256 hopAmountIn;
    uint256 nextIndex;
    uint256 startGas;
    uint256 i;
    uint256 lastAmountOut;
    uint256 hopsLength;
    uint256 amountIn;
    uint256 amountInAcc;
    address fromAssetAddress;
    address toAssetAddress;
    address currentFromAssetAddress;
    address hopToAssetAddress;
}

error RouterAmmCallFailed(bytes returnData);
error RouterInvalidPath();
error RouterExpiredTransaction();
error RouterInsufficientOutputAmount();
error RouterInvalidAmountIn();
error RouterInvalidProtocol();
error RouterInvalidHops();
error RouterInvalidSender();

library LibRouter {
    using LibAsset for address;
    using LibBytes for bytes;
    using LibUint256Array for uint256[];

    function getHopParams(
        bytes32 data,
        bytes memory addresses,
        bytes memory poolData,
        uint256[] memory amountIns
    ) public pure returns (uint16 ammId, uint256 amountIn, address[] memory path, bytes[] memory poolDataList) {
        uint256 pl;
        uint256 pdl;
        uint256 poolDataPosition;
        uint256 poolDataLength;

        assembly {
            amountIn := mload(add(amountIns, add(32, mul(shr(248, data), 32))))
            ammId := shr(240, shl(8, data))
            pl := shr(248, shl(24, data))
            pdl := shr(248, shl(32, data))
        }

        path = new address[](pl);

        assembly {
            let i := 0
            let pathPosition := add(path, 32)

            for {

            } lt(i, pl) {
                i := add(i, 1)
                pathPosition := add(pathPosition, 32)
            } {
                mstore(
                    pathPosition,
                    shr(
                        96,
                        mload(add(add(addresses, 32), mul(shr(248, shl(mul(add(5, i), 8), data)) /* pathIndex */, 20)))
                    )
                )
            }
        }

        poolDataList = new bytes[](pdl);

        for (uint256 i = 0; i < pdl; ) {
            assembly {
                poolDataPosition := shr(248, shl(mul(add(10, i), 8), data))
                poolDataLength := shr(240, shl(mul(add(14, mul(i, 2)), 8), data))
            }

            poolDataList[i] = poolData.slice(poolDataPosition, poolDataLength);

            unchecked {
                i++;
            }
        }
    }

    function swap(
        SwapArgs memory swapArgs,
        bool estimateGas
    ) internal returns (uint256 amountOut, uint256[] memory gasUsed) {
        AppStorage storage s = LibMagpieRouter.getStorage();
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();

        SwapState memory ss = SwapState({
            hopAmmId: 0,
            hopAmountIn: 0,
            nextIndex: 0,
            startGas: 0,
            i: 0,
            lastAmountOut: 0,
            hopsLength: swapArgs.hops.length,
            amountIn: swapArgs.amountIns.sum(),
            amountInAcc: 0,
            fromAssetAddress: swapArgs.addresses.toAddress(20),
            toAssetAddress: swapArgs.addresses.toAddress(40),
            currentFromAssetAddress: swapArgs.addresses.toAddress(20),
            hopToAssetAddress: address(0)
        });

        if (ss.fromAssetAddress.isNative()) {
            ss.fromAssetAddress.deposit(s.weth, msg.value);
            ss.fromAssetAddress = s.weth;
            ss.currentFromAssetAddress = s.weth;
        } else if (ss.toAssetAddress.isNative()) {
            ss.toAssetAddress = s.weth;
        }

        HopParams memory hopParams = HopParams({
            ammId: 0,
            amountIn: 0,
            poolDataList: new bytes[](0),
            path: new address[](0)
        });

        Hop memory hop = Hop({
            addr: address(0),
            amountIn: 0,
            recipient: address(this),
            poolDataList: new bytes[](0),
            path: new address[](0)
        });

        if (estimateGas) {
            gasUsed = new uint256[](ss.hopsLength);
        }

        for (ss.i; ss.i < ss.hopsLength; ) {
            if (ss.i == 0) {
                (hopParams.ammId, hopParams.amountIn, hopParams.path, hopParams.poolDataList) = getHopParams(
                    swapArgs.hops[ss.i],
                    swapArgs.addresses,
                    swapArgs.poolData,
                    swapArgs.amountIns
                );
            }

            ss.hopAmmId = hopParams.ammId;
            ss.hopAmountIn = hopParams.amountIn;
            hop.path = hopParams.path;
            hop.poolDataList = hopParams.poolDataList;
            hop.addr = s.amms[ss.hopAmmId].addr;

            ss.nextIndex = ss.i + 1;
            if (ss.nextIndex < ss.hopsLength) {
                (hopParams.ammId, hopParams.amountIn, hopParams.path, hopParams.poolDataList) = getHopParams(
                    swapArgs.hops[ss.nextIndex],
                    swapArgs.addresses,
                    swapArgs.poolData,
                    swapArgs.amountIns
                );
            }

            if (hop.path.length < 2) {
                revert RouterInvalidPath();
            }

            if (hop.path[0].isNative()) {
                hop.path[0] = s.weth;
            } else if (hop.path[hop.path.length - 1].isNative()) {
                hop.path[hop.path.length - 1] = s.weth;
            }

            if ((ss.currentFromAssetAddress == ss.toAssetAddress || ss.i == 0) && ss.fromAssetAddress == hop.path[0]) {
                ss.currentFromAssetAddress = ss.fromAssetAddress;
                hop.amountIn = ss.hopAmountIn;
                ss.amountInAcc += hop.amountIn;
            } else {
                hop.amountIn = ss.lastAmountOut;
            }

            ss.hopToAssetAddress = hop.path[hop.path.length - 1];

            if (ss.i == ss.hopsLength - 1 && ss.hopToAssetAddress != ss.toAssetAddress) {
                revert RouterInvalidHops();
            }

            if (ss.currentFromAssetAddress != hop.path[0]) {
                revert RouterInvalidPath();
            }

            if (s.amms[ss.hopAmmId].protocolId == 0) {
                revert RouterInvalidProtocol();
            }

            address facet = ds.selectorToFacetAndPosition[s.amms[ss.hopAmmId].selector].facetAddress;
            if (facet == address(0)) {
                revert RouterInvalidProtocol();
            }
            bytes memory ammCall = abi.encodeWithSelector(s.amms[ss.hopAmmId].selector, hop);

            if (estimateGas) {
                ss.startGas = gasleft();
            }

            (bool success, bytes memory data) = address(facet).delegatecall(ammCall);

            if (estimateGas) {
                gasUsed[ss.i] = ss.startGas - gasleft();
            }

            if (!success) {
                revert RouterAmmCallFailed(data);
            }

            ss.lastAmountOut = abi.decode(data, (uint256));

            ss.currentFromAssetAddress = ss.hopToAssetAddress;

            unchecked {
                ss.i++;
            }
        }

        amountOut = ss.toAssetAddress.getBalance();

        if (amountOut < swapArgs.amountOutMin || amountOut == 0) {
            revert RouterInsufficientOutputAmount();
        }

        if (ss.amountIn != ss.amountInAcc) {
            revert RouterInvalidAmountIn();
        }

        ss.toAssetAddress.transfer(s.magpieAggregatorAddress, amountOut);
    }

    function enforceDeadline(uint256 deadline) internal view {
        if (deadline < block.timestamp) {
            revert RouterExpiredTransaction();
        }
    }

    function enforceIsMagpieAggregator() internal view {
        AppStorage storage s = LibMagpieRouter.getStorage();

        if (msg.sender != s.magpieAggregatorAddress) {
            revert RouterInvalidSender();
        }
    }

    event AddAmm(address indexed sender, uint16 ammId, Amm amm);

    function addAmm(uint16 ammId, Amm memory amm) internal {
        AppStorage storage s = LibMagpieRouter.getStorage();

        s.amms[ammId] = amm;

        emit AddAmm(msg.sender, ammId, amm);
    }

    event AddAmms(address indexed sender, uint16[] ammIds, Amm[] amms);

    function addAmms(uint16[] memory ammIds, Amm[] memory amms) internal {
        AppStorage storage s = LibMagpieRouter.getStorage();

        uint256 i;
        uint256 l = amms.length;
        for (i = 0; i < l; ) {
            s.amms[ammIds[i]] = amms[i];

            unchecked {
                i++;
            }
        }

        emit AddAmms(msg.sender, ammIds, amms);
    }

    event RemoveAmm(address indexed sender, uint16 ammId);

    function removeAmm(uint16 ammId) internal {
        AppStorage storage s = LibMagpieRouter.getStorage();

        delete s.amms[ammId];

        emit RemoveAmm(msg.sender, ammId);
    }

    event UpdateCurveSettings(address indexed sender, CurveSettings curveSettings);

    function updateCurveSettings(address addressProvider) internal {
        AppStorage storage s = LibMagpieRouter.getStorage();

        s.curveSettings = CurveSettings({
            mainRegistry: IAddressProvider(addressProvider).get_address(0),
            cryptoRegistry: IAddressProvider(addressProvider).get_address(5),
            cryptoFactory: IAddressProvider(addressProvider).get_address(6)
        });

        emit UpdateCurveSettings(msg.sender, s.curveSettings);
    }

    event UpdateWeth(address indexed sender, address weth);

    function updateWeth(address weth) internal {
        AppStorage storage s = LibMagpieRouter.getStorage();

        s.weth = weth;

        emit UpdateWeth(msg.sender, weth);
    }

    event UpdateMagpieAggregatorAddress(address indexed sender, address magpieAggregatorAddress);

    function updateMagpieAggregatorAddress(address magpieAggregatorAddress) internal {
        AppStorage storage s = LibMagpieRouter.getStorage();

        s.magpieAggregatorAddress = magpieAggregatorAddress;

        emit UpdateMagpieAggregatorAddress(msg.sender, magpieAggregatorAddress);
    }
}

