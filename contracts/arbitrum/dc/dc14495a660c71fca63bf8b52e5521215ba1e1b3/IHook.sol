pragma solidity 0.8.18;

import {ERC20} from "./ERC20.sol";

interface IHook {
    function beforeDeposit() external;

    function afterDeposit(uint256 amount) external;

    function beforeWithdraw(uint256 amount) external;

    function beforeDeploy() external;

    function afterDeploy() external;

    function beforeClose() external;

    function afterClose() external;

    function afterCloseTransferAssets() external view returns (ERC20[] memory);

    function totalAssets() external view returns (uint256);

    function availableAmounts(
        address[] memory vaults,
        uint256[] memory epochIds,
        uint256 weightStrategy
    ) external view returns (uint256[] memory);
}

