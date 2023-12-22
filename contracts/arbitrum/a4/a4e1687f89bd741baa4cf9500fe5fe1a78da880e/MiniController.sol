// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "./IERC20.sol";
import "./SafeMath.sol";
import "./Address.sol";
import "./SafeERC20.sol";

import "./IStrategy.sol";

// MiniController is inherited by the Vault.
// It just holds important addresses, fee data, and setters.
contract MiniController {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    address public governance;
    address public strategist;
    address public sushiswap;
    address public strategy;
    IERC20 public token; // The MIM-2CRV LP token

    uint256 public protocolFee = 500; // 5%
    uint256 public constant MAX_FEE = 10000;

    // Event declarations
    event StrategySet(address _strategy);
    event GovernanceSet(address _governance);
    event SushiSwapSet(address _sushi);
    event ProtocolFeeSet(uint256 _fee);
    event StrategistSet(address _strategist);
    event RewardsSet(address _address);

    constructor(address _token, address _sushiswap) {
        governance = msg.sender;
        strategist = msg.sender;
        token = IERC20(_token);
        sushiswap = _sushiswap;
    }

    function _onlyGovernance() internal view {
        require(msg.sender == governance, "!governance");
    }

    function _onlyStrategist() internal view {
        require(msg.sender == strategist, "!strategist");
    }

    function _onlyAuthorized() internal view {
        require(msg.sender == strategist || msg.sender == governance, "!authorized");
    }

    modifier onlyGovernance() {
        _onlyGovernance();
        _;
    }

    modifier onlyStrategist() {
        _onlyGovernance();
        _;
    }

    modifier onlyAuthorized() {
        _onlyAuthorized();
        _;
    }

    function setStrategist(address _strategist) public onlyGovernance {
        strategist = _strategist;
        emit StrategistSet(strategist);
    }

    function setProtocolFee(uint256 _fee) public onlyGovernance {
        protocolFee = _fee;
        emit ProtocolFeeSet(protocolFee);
    }

    function setSushiswap(address _sushi) public onlyGovernance {
        sushiswap = _sushi;
        emit SushiSwapSet(sushiswap);
    }

    function setGovernance(address _governance) public onlyGovernance {
        governance = _governance;
        emit GovernanceSet(governance);
    }

    function setStrategy(address _strategy) public onlyAuthorized {
        if (strategy != address(0)) {
            IStrategy(strategy).withdrawAll();
        }
        strategy = _strategy;
        emit StrategySet(strategy);
    }

    function strategyBalance() external view returns (uint256) {
        return IStrategy(strategy).balanceOf();
    }
}

