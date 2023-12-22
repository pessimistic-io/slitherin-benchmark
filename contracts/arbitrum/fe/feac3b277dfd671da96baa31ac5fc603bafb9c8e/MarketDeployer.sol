pragma solidity ^0.8.0;

import "./PriceFeedsMarket.sol";
import "./RealityETHMarket.sol";


library MarketDeployer {

    function deployPriceFeedsMarket(
        address _factoryContractAddress,
        string memory _question,
        uint256[5] memory _outcomes,
        uint256 _numberOfOutcomes,
        uint256 _wageDeadline,
        uint256 _resolutionDate,
        address _priceFeedAddress,
        address _priceFeederAddress
    ) external returns(address){
        address _marketAddress = address(
            new PriceFeedsMarket(
                _factoryContractAddress,
                _question,
                _outcomes,
                _numberOfOutcomes,
                _wageDeadline,
                _resolutionDate,
                _priceFeedAddress,
                _priceFeederAddress
            )
        );
        return _marketAddress;
    }

    function deployRealityETHMarket(
        address _factoryContractAddress,
        string memory _question,
        uint256 _numberOfOutcomes,
        uint256 _wageDeadline,
        uint256 _resolutionDate,
        uint256 _template_id,
        address _arbitrator,
        uint32 _timeout,
        uint256 _nonce,
        address _realityEthAddress,
        uint256 _min_bond
    ) external returns(address){
        address _marketAddress = address(
            new RealityETHMarket(
                _factoryContractAddress,
                _question,
                _numberOfOutcomes,
                _wageDeadline,
                _resolutionDate,
                _template_id,
                _arbitrator,
                _timeout,
                _nonce,
                _realityEthAddress,
                _min_bond
            )
        );
        return _marketAddress;
    }
}
