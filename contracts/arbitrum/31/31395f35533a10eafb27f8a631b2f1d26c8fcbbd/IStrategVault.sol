// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./IERC20Metadata.sol";
import "./ERC4626.sol";
import "./draft-ERC20Permit.sol";
import "./Ownable.sol";
import "./Strings.sol";
import "./IStrategStepRegistry.sol";
import "./IStratStep.sol";

// import "hardhat/console.sol";

interface IStrategVault {

    function transferFrom(address from, address to, uint256 amount) external;

    function setStrat(
        uint256[] memory _stratStepsIndex,
        bytes[] memory _stratStepsParameters,
        uint256[] memory _harvestStepsIndex,
        bytes[] memory _harvestStepsParameters,
        uint256[] memory _oracleStepsIndex,
        bytes[] memory _oracleStepsParameters
    ) external;

    function getStrat()
        external
        view
        returns (
            address[] memory _stratSteps,
            bytes[] memory _stratStepsParameters,
            address[] memory _harvestSteps,
            bytes[] memory _harvestStepsParameters,
            address[] memory _oracleSteps,
            bytes[] memory _oracleStepsParameters
        );

    function registry() external view  returns (address);
    function feeCollector() external view  returns (address);
    function factory() external view  returns (address);
    function totalAssets() external view  returns (uint256);
    function asset() external view  returns (address);

    function harvest() external;

    /** @dev See {IERC4262-deposit}. */
    function deposit(uint256 assets, address receiver)
        external
        returns (uint256);

    /** @dev See {IERC4262-mint}. */
    function mint(uint256 shares, address receiver)
        external
        returns (uint256);

    /** @dev See {IERC4262-withdraw}. */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) external returns (uint256);

    /** @dev See {IERC4262-redeem}. */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) external returns (uint256);

    function permit(
        address owner,
        address spender,
        uint256 amount,
        uint256 deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    )  external;
}

