// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;
pragma abicoder v2;

import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { Initializable } from "./Initializable.sol";
import { Governable } from "./Governable.sol";
import { IOracleRouter } from "./IOracleRouter.sol";
import { IBridge } from "./IBridge.sol";
import "./Helpers.sol";
import { OvnMath } from "./OvnMath.sol";
import { SafeMath } from "./SafeMath.sol";
import { StableMath } from "./StableMath.sol";
import { IBridgePlace } from "./IBridgePlace.sol";
import "./console.sol";

contract Bridge is Initializable, Governable, IBridge {
    using SafeERC20 for IERC20;
    using OvnMath for uint256;
    using StableMath for uint256;
    using SafeMath for uint256;

    uint256 public bridgePlacesLength;
    mapping(string => address) public bridgePlaces;

    mapping(address => address) public tokenToBridgePlace;

    // default split parts for common swap request
    address public oracleRouter;
    uint256 public slippage;

    function setParams(address _oracleRouter, uint256 _slippage) external onlyGovernor {
        oracleRouter = _oracleRouter;
        slippage = _slippage;
        emit ParamsUpdated(oracleRouter, slippage);
    }

    function addBridgePlace(address _bridgePlace, string calldata bridgePlaceType) public onlyGovernor {
        require(_bridgePlace != address(0), "!addr(0)");
        bridgePlaces[bridgePlaceType] = _bridgePlace;
        bridgePlacesLength++;
    }

    function bridgePlaceRemove(string memory _bridgePlaceType) external onlyGovernor {
        delete bridgePlaces[_bridgePlaceType];
        bridgePlacesLength--;
    }

    function setBridgePlaceToken(address _token, address _bridgePlace) external onlyGovernor {
        tokenToBridgePlace[_token] = _bridgePlace;
    }

    function removeBridgePlaceToken(address _token) external onlyGovernor {
        delete tokenToBridgePlace[_token];
    }

    function send(
        address _token,
        uint256 _destinationChainId,
        address _destinationAddress,
        uint256 _amount,
        uint256 _minAmount,
        bool _isNative
    ) external payable {
        address _bridgePlace = tokenToBridgePlace[_token];
        require(_bridgePlace != address(0), "!bridgePlace");
        if (_isNative) {
            require(msg.value == _amount, "!value");
            IBridgePlace(_bridgePlace).send{value: _amount}(
                _token,
                _destinationChainId,
                _destinationAddress,
                _amount,
                _minAmount,
                true
            );
        } else {
            IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
            IERC20(_token).safeApprove(_bridgePlace, _amount);
            IBridgePlace(_bridgePlace).send(
                _token,
                _destinationChainId,
                _destinationAddress,
                _amount,
                _minAmount,
                false
            );
        }
        console.log("msg.value", msg.value);
    }

    // allow this contract to receive ether
    receive() external payable {}
}

