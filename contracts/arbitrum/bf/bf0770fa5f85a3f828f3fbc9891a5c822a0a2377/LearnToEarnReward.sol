// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.3;
import "./IERC20.sol";
import "./Ownable.sol";
import "./SafeMath.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./StringLibrary.sol";
import "./BytesLibrary.sol";
import "./ILearnToEarnReward.sol";

interface ILearnToken is IERC20 {
    function mint(address receipient, uint256 amount) external;
}
contract LearnToEarnReward is ILearnToEarnReward, Ownable, ReentrancyGuard {

    using StringLibrary for string;
    using BytesLibrary for bytes32;
    using SafeERC20 for IERC20;
    using SafeMath for uint;
    uint public claimRate = 1;
    ILearnToken public learnToken;
    address private signer;

    mapping(uint => ClaimHistory) claimHistories;
    mapping(address => uint[]) userClaimIds;

    event ClaimEvent(address user, uint claimAmount,  uint numberOfCoin);
    event CoinPerLearnTokenChangedEvent(uint oldValue, uint newValue);


    constructor(address _signer, ILearnToken _learnToken) {
        signer = _signer;
        learnToken = _learnToken;
    }


    fallback () external payable {
        revert(); // Not allow sending BNB to this contract
    }

    receive() external payable {
        revert(); // Not allow sending BNB to this contract
    }

   
    // Convert earned coin to Learn token
    function claim(uint salt, uint coinValue, uint8 v, bytes32 r, bytes32 s) override  external nonReentrant {

        uint claimingCoin = coinValue.mul(claimRate);
        require(validSignature(salt, claimingCoin, v ,r ,s), "withdraw: invalid signature");
        ClaimHistory storage claimHistory =claimHistories[salt];
        require(claimHistory.user == address (0), "withdraw: invalid salt");
        claimHistory.user = msg.sender;
        claimHistory.timestamp = block.timestamp;
        claimHistory.learnTokenValue = claimingCoin;
        claimHistory.coinValue = coinValue;

        learnToken.mint(msg.sender, claimingCoin);
        emit ClaimEvent(msg.sender, claimingCoin, coinValue);
    }

    function validSignature(uint salt, uint gameCoinsValue, uint8 v, bytes32 r, bytes32 s) internal view returns(bool) {
        return keccak256(abi.encode(salt, gameCoinsValue, msg.sender)).toString().recover(v, r, s) == signer;
    }


    function getClaimHistory(uint salt) public override view returns(ClaimHistory memory) {
        return claimHistories[salt];
    }
    function getClaimIds(address user) public override view returns(uint[] memory) {
        return userClaimIds[user];

    }

    function getClaimHistories(address user) public override view returns(ClaimHistory[] memory) {
        uint[] memory _salts = getClaimIds(user);

        ClaimHistory[] memory _claimHistories = new ClaimHistory[](_salts.length);

        for(uint i = 0; i < _salts.length; i++) {
            _claimHistories[i] = getClaimHistory(_salts[i]);
        }
        return _claimHistories;
    }


    function changeRate(uint _coinPerLearnTokenRate) external onlyOwner {
        uint oldValue = _coinPerLearnTokenRate;
        claimRate = _coinPerLearnTokenRate;
        emit CoinPerLearnTokenChangedEvent(oldValue, claimRate);
    }

    function changeSigner(address _signer) external onlyOwner {
        signer = _signer;
    }
    function isSigner(address _signer) external view returns(bool) {
        return signer == _signer;
    }


}

