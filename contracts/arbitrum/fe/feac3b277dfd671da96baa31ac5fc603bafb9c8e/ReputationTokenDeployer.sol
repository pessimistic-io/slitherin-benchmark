pragma solidity ^0.8.0;

import "./ReputationToken.sol";


library ReputationTokenDeployer {

    function deploy(
        string memory _topic,
        string memory _symbol
    ) external returns(address){
        address _reputationTokenAddress = address(
            new ReputationToken(
                _topic,
                _symbol
            )
        );
        return _reputationTokenAddress;
    }
}
