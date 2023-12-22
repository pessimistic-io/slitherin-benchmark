// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

import "./IERC20Metadata.sol";
import "./IFeeWithdraw.sol";
import "./ISharesFeeStore.sol";

interface IVAMM is IFeeWithdraw {
    event Trade(
        address indexed trader,
        bool isBuy,
        address shareId,
        uint256 amount
    );
    event UpdateMarketPrice(address shareId, uint256 newMarketPrice);
    event CollectFees(
        address shareId,
        address indexed trader,
        uint256 protocolFees,
        uint256 shareOwnerFees
    );
    event UpdateShareFeeStore(
        address shareId,
        address oldShareFeeStore,
        address newShareFeeStore
    );
    event UpdateProtocolFeeStore(
        address oldProtocolFeeStore,
        address newProtocolFeeStore
    );

    function mint(
        address shareId,
        uint256 mintAmount,
        uint256 maxPayAmount,
        address recipient,
        bytes memory protocolFeeData,
        bytes memory shareFeeData
    ) external;

    function burn(
        address shareId,
        uint256 brunAmount,
        uint256 minReceiveAmount,
        address recipient,
        bytes memory protocolFeeData,
        bytes memory shareFeeData
    ) external;

    function aggregateMint(
        address shareId,
        uint256 mintAmount,
        uint256 maxPayAmount,
        address[] memory recipients,
        bytes memory protocolFeeData,
        bytes memory shareFeeData
    ) external;

    function shareInitialize(address shareId, ISharesFeeStore) external;

    function getShareFeeStore(
        address shareId
    ) external view returns (ISharesFeeStore);
}

