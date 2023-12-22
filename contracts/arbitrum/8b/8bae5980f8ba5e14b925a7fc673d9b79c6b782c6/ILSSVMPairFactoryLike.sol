// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {LSSVMRouter} from "./LSSVMRouter.sol";


// TODO
interface ILSSVMPairFactoryLike {
    enum PairVariant {
        ENUMERABLE_ETH,
        MISSING_ENUMERABLE_ETH,
        ENUMERABLE_ERC20,
        MISSING_ENUMERABLE_ERC20,
        MISSING_ENUMERABLE_1155_ETH,
        MISSING_ENUMERABLE_1155_ERC20
    }

    function protocolFeeMultiplier() external view returns (uint256);

    function protocolFeeRecipient() external view returns (address payable);

    function callAllowed(address target) external view returns (bool);

    function operatorProtocolFeeRecipients(address nft,address operator) external view returns (address);

    function operatorProtocolFeeMultipliers(address nft,address operator) external view returns (uint256);

    function getNftOperators(address nft) external view returns (address[] memory);

    function routerStatus(LSSVMRouter router)
        external
        view
        returns (bool allowed, bool wasEverAllowed);

    function isPair(address potentialPair, PairVariant variant)
        external
        view
        returns (bool);
}

