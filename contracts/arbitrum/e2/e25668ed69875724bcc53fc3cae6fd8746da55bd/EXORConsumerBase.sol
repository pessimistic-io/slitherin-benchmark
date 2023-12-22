pragma solidity ^0.6.10;

import "./SafeMath.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
interface IEXOR {
    function randomnessRequest(
        uint256 _consumerSeed,
        uint256 _feePaid,
        address _feeToken
    ) external;
}

contract EXORRequestIDBase {

    //special process for proxy
    bytes32 public _keyHash;

    function makeVRFInputSeed(
        uint256 _userSeed,
        address _requester,
        uint256 _nonce
    ) internal pure returns ( uint256 ) {

        return uint256(keccak256(abi.encode(_userSeed, _requester, _nonce)));
    }

    function makeRequestId(
        uint256 _vRFInputSeed
    ) internal view returns (bytes32) {

        return keccak256(abi.encodePacked(_keyHash, _vRFInputSeed));
    }
}

abstract contract EXORConsumerBase is EXORRequestIDBase {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /* ================================================== STATE VARIABLES ================================================== */
    // @notice requesting times of this consumer
    uint256 private nonces;
    // @notice reward address
    address public feeToken;
    // @notice EXORandomness address
    address private EXORAddress;
    // @notice appointed data source map
    mapping(address => bool) public datasources;

    bool private onlyInitEXOROnce;


    /* ================================================== CONSTRUCTOR ================================================== */

    function initEXORConsumerBase (
        address  _EXORAddress,
        address _feeToken,
        address _datasource
    ) public {
        require(!onlyInitEXOROnce, "exorBase already initialized");
        onlyInitEXOROnce = true;

        EXORAddress = _EXORAddress;
        feeToken = _feeToken;
        datasources[_datasource] = true;


    }

    /* ================================================== MUTATIVE FUNCTIONS ================================================== */
    // @notice developer needs to overwrites this function, and the total gas used is limited less than 200K
    //         it will be emitted when a bot put a random number to this consumer
    function fulfillRandomness(
        bytes32 requestId,
        uint256 randomness
    ) internal virtual;

    // @notice developer needs to call this function in his own logic contract, to ask for a random number with a unique request id
    // @param _seed seed number generated from logic contract
    // @param _fee reward number given for this single request
    function requestRandomness(
        uint256 _seed,
        uint256 _fee
    )
    internal
    returns (
        bytes32 requestId
    )
    {
        IERC20(feeToken).safeApprove(EXORAddress, 0);
        IERC20(feeToken).safeApprove(EXORAddress, _fee);

        IEXOR(EXORAddress).randomnessRequest(_seed, _fee, feeToken);

        uint256 vRFSeed  = makeVRFInputSeed(_seed, address(this), nonces);
        nonces = nonces.add(1);
        return makeRequestId(vRFSeed);
    }

    // @notice only EXORandomness contract can call this function
    // @param requestId a specific request id
    // @param randomness a random number
    function rawFulfillRandomness(
        bytes32 requestId,
        uint256 randomness
    ) external {
        require(msg.sender == EXORAddress, "Only EXORandomness can fulfill");
        fulfillRandomness(requestId, randomness);
    }
}

