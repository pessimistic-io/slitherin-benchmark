// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import "./ERC20Upgradeable.sol";
import "./ERC20.sol";
import "./IController.sol";
import "./Constants.sol";

contract BaseStrategy is ERC20Upgradeable {
    struct MinPerValueLimit {
        uint256 lower;
        uint256 upper;
    }

    IController internal controller;

    uint256 public vaultId;

    address internal usdc;

    uint256 internal assetId;

    MinPerValueLimit internal minPerValueLimit;

    address public operator;

    event OperatorUpdated(address operator);

    modifier onlyOperator() {
        require(operator == msg.sender, "BaseStrategy: caller is not operator");
        _;
    }

    constructor() {}

    function initialize(
        address _controller,
        uint256 _assetId,
        MinPerValueLimit memory _minPerValueLimit,
        string memory _name,
        string memory _symbol
    ) internal onlyInitializing {
        ERC20Upgradeable.__ERC20_init(_name, _symbol);

        controller = IController(_controller);

        assetId = _assetId;

        minPerValueLimit = _minPerValueLimit;

        DataType.AssetStatus memory asset = controller.getAsset(Constants.STABLE_ASSET_ID);

        usdc = asset.token;

        operator = msg.sender;
    }

    /**
     * @notice Sets new operator
     * @dev Only operator can call this function.
     * @param _newOperator The address of new operator
     */
    function setOperator(address _newOperator) external onlyOperator {
        require(_newOperator != address(0));
        operator = _newOperator;

        emit OperatorUpdated(_newOperator);
    }
}

