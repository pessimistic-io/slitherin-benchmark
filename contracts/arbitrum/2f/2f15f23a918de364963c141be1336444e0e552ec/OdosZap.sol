//SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0 <0.9.0;

import "./Initializable.sol";
import "./AccessControlUpgradeable.sol";
import "./UUPSUpgradeable.sol";
import "./IERC20.sol";
import "./IERC20Metadata.sol";

import "./OvnMath.sol";
import "./Chronos.sol";

import "./console.sol";

contract OdosZap is Initializable, AccessControlUpgradeable, UUPSUpgradeable {
    uint256 constant MAX_UINT_VALUE = type(uint256).max;

    uint256 public stakeSlippageBP;
    address public odosRouter;

    struct OutputToken {
        address tokenAddress;
        address receiver;
    }

    struct InputToken {
        address tokenAddress;
        uint256 amountIn;
    }

    struct SwapData {
        InputToken[] inputs;
        OutputToken[] outputs;
        bytes data;
    }

    struct StakeData {
        address gauge;
        address pair;
        address router;
        address token;
    }

    // Контракт успешной транзакции создает события:
    // - Сколько подали токенов на вход
    // - Сколько получили в результате обмена
    // - Сколько положили в пул
    // - Сколько вернули пользователю

    event InputTokens(uint256[] amountsIn, address[] tokensIn);

    event OutputTokens(uint256[] amountsOut, address[] tokensOut);

    event PutIntoPool(uint256[] amountsPut, address[] tokensPut);

    event ReturnedToUser(uint256[] amountsReturned, address[] tokensReturned);

    event UpdateSlippages(uint256 stakeSlippageBP);

    function initialize() public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        stakeSlippageBP = 4;
    }

    modifier onlyAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "!Admin");
        _;
    }

    receive() external payable {}

    function _authorizeUpgrade(address newImplementation) internal override onlyAdmin {}


    function setSlippages(uint256 _stakeSlippageBP) external onlyAdmin {
        stakeSlippageBP = _stakeSlippageBP;

        emit UpdateSlippages(stakeSlippageBP);
    }

    function _prepareSwap(SwapData memory swapData) internal {
        for (uint256 i = 0; i < swapData.outputs.length; i++) {
            for (uint256 j = 0; j < i; j++) {
                require(
                    swapData.outputs[i].tokenAddress != swapData.outputs[j].tokenAddress,
                    "Duplicate output tokens"
                );
                require(
                    swapData.outputs[i].receiver == address(this),
                    "Receiver of swap is not this contract"
                );
            }
        }

        for (uint256 i = 0; i < swapData.inputs.length; i++) {
            // different inputs
            for (uint256 j = 0; j < i; j++) {
                require(
                    swapData.inputs[i].tokenAddress != swapData.inputs[j].tokenAddress,
                    "Duplicate input tokens"
                );
            }
            // no identical inputs and outputs
            for (uint256 j = 0; j < swapData.outputs.length; j++) {
                require(
                    swapData.inputs[i].tokenAddress != swapData.outputs[j].tokenAddress,
                    "Duplicate input and output"
                );
            }

            IERC20 asset = IERC20(swapData.inputs[i].tokenAddress);
            asset.transferFrom(msg.sender, address(this), swapData.inputs[i].amountIn);
            asset.approve(odosRouter, swapData.inputs[i].amountIn);
        }
    }

    function _swap(SwapData memory swapData) internal returns (address[] memory, uint256[] memory) {
        (bool success,) = odosRouter.call{value : 0}(swapData.data);
        require(success, "router swap invalid");

        // Emit events
        address[] memory tokensIn = new address[](swapData.inputs.length);
        uint256[] memory amountsIn = new uint256[](swapData.inputs.length);
        for (uint256 i = 0; i < swapData.inputs.length; i++) {
            tokensIn[i] = swapData.inputs[i].tokenAddress;
            amountsIn[i] = swapData.inputs[i].amountIn;
        }
        emit InputTokens(amountsIn, tokensIn);

        address[] memory tokensOut = new address[](swapData.outputs.length);
        uint256[] memory amountsOut = new uint256[](swapData.outputs.length);
        for (uint256 i = 0; i < swapData.outputs.length; i++) {
            tokensOut[i] = swapData.outputs[i].tokenAddress;
            amountsOut[i] = IERC20(tokensOut[i]).balanceOf(swapData.outputs[i].receiver);
        }
        emit OutputTokens(amountsOut, tokensOut);
        return (tokensOut, amountsOut);
    }
}

