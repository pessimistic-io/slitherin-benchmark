// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./IGaugeFactoryV2.sol";
import "./MaGauge.sol";

import "./Clones.sol";
import "./OwnableUpgradeable.sol";

interface IGauge{
    function setDistribution(address _distro) external;
    function initialize(
        address _rewardToken,
        address _ve,
        address _token,
        address _distribution,
        address _internal_bribe,
        address _external_bribe,
        bool _isForPair
    ) external;

}
contract GaugeFactoryV3 is OwnableUpgradeable {
    
    uint256[50] __gap;
    
    address public last_gauge;
    address public gaugeImplementation;
    

    function initialize(address _gaugeImplementation) initializer  public {
        __Ownable_init();
        gaugeImplementation = _gaugeImplementation;
    }

    function createGaugeV2(address _rewardToken,address _ve,address _token,address _distribution, address _internal_bribe, address _external_bribe, bool _isPair) external returns (address) {
        //last_gauge = address(new MaGauge(_rewardToken,_ve,_token,_distribution,_internal_bribe,_external_bribe,_isPair) );
        last_gauge = Clones.clone(gaugeImplementation);
        IGauge(last_gauge).initialize(_rewardToken,_ve,_token,_distribution,_internal_bribe,_external_bribe,_isPair);
        return last_gauge;
    }

    function setDistribution(address _gauge, address _newDistribution) external onlyOwner {
        IGauge(_gauge).setDistribution(_newDistribution);
    }

}

