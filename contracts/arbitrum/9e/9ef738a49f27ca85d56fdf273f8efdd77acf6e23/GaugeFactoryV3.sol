// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./IGaugeFactoryV3.sol";
import "./GaugeV3.sol";

import "./OwnableUpgradeable.sol";

interface IGauge {
    function setDistribution(address _distro) external;

    function setGaugeRewarder(address _distro) external;
}

contract GaugeFactoryV3 is IGaugeFactory, OwnableUpgradeable {
    address public last_gauge;

    function initialize() public initializer {
        __Ownable_init();
    }

    function createGaugeV3(
        address _rewardToken,
        address _ve,
        address _token,
        address _distribution,
        address _internal_bribe,
        address _external_bribe,
        bool _isPair
    ) external returns (address) {
        last_gauge = address(
            new GaugeV3(
                _rewardToken,
                _ve,
                _token,
                _distribution,
                _internal_bribe,
                _external_bribe,
                _isPair
            )
        );
        return last_gauge;
    }

    function setDistribution(address _gauge, address _newDistribution)
        external
        onlyOwner
    {
        IGauge(_gauge).setDistribution(_newDistribution);
    }

    function setGaugeRewarder(address _gauge, address _newRewarder)
        external
        onlyOwner
    {
        IGauge(_gauge).setGaugeRewarder(_newRewarder);
    }
}

