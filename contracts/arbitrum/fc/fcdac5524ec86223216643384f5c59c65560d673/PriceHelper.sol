// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.7.6;

import "./IManager.sol";
import "./SafeMath.sol";

contract PriceHelper {
    using SafeMath for uint256;

    uint256 public constant RATE_PRECISION = 1e6;
    address public manager;
    mapping(string => uint256) public maxSlipPoints;

    event MaxSlipPointSettled(uint256 maxSlipPoint);

    constructor(address _manager) {
        require(_manager != address(0), "PriceHelper: invalid manager");
        manager = _manager;
    }

    modifier onlyController() {
        require(IManager(manager).checkController(msg.sender), "PriceHelper: Must be controller");
        _;
    }

    function setMaxSlipPoint(string memory token, uint256 _maxSlipPoint) external onlyController {
        maxSlipPoints[token] = _maxSlipPoint;
        emit MaxSlipPointSettled(_maxSlipPoint);
    }

    function getSlipPointPrice(string memory token, uint256 price, uint256 value, uint256 maxValue, bool maximise) public view returns (uint256) {
        uint256 slipPoint;
        if (value >= maxValue) {
            slipPoint = maxSlipPoints[token];
        }else{
            slipPoint = maxSlipPoints[token].mul(value).div(maxValue);
        }

        if (maximise) {
            return price.mul(RATE_PRECISION.add(slipPoint)).div(RATE_PRECISION);
        } else {
            return price.mul(RATE_PRECISION.sub(slipPoint)).div(RATE_PRECISION);
        }
    }
}

