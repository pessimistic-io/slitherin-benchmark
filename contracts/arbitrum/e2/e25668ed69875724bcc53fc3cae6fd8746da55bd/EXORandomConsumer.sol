pragma solidity ^0.6.10;

import "./EXORConsumerBase.sol";
import "./Ownable.sol";


contract EXORandomConsumer is EXORConsumerBase {

    event RequestNonce(uint256 indexed nonce);
    event DemoRandom(bytes32 indexed requestId, uint256 indexed randomness);
    event DataSourceChanged(address indexed datasource, bool indexed allowed);


    /**
    * Constructor inherits EXORConsumerBase
    *
    * Network: OEC Testnet
    * _EXORAddress: 0x20506127Af03E02cabB67020962e8152087DfF3f
    * _feeToken: 0xc474786670dda7763ec2733df674dd3fa1ddc819 (an erc20 token address)
    * _datasource: 0x898527f28d6abe526308a6d18157ed1249c5bf1e
    */
 /*   constructor(address _EXORAddress, address _feeToken, address _datasource) EXORConsumerBase(_EXORAddress, _feeToken, _datasource) public {


    }*/

    function fulfillRandomness(bytes32 requestId, uint256 randomness) internal override {
        emit DemoRandom(requestId, randomness);

        //根据reqId取order
        //讲随机数存入order
    }

    /**
     * Requests randomness to EXORandomness
     */
    function requestRandomness(uint256 timer) external {
        requestRandomness(timer, 100);

        timer = timer + 1;
        emit RequestNonce(timer);
    }
}
