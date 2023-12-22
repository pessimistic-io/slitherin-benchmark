pragma solidity =0.8.16;

import "./Ownable.sol";
import "./PRBMathUD60x18.sol";

import "./IArkenPairLongTerm.sol";
import "./IArkenOptionRewarder.sol";
import "./IArkenOptionNFT.sol";

// import 'hardhat/console.sol';

contract ArkenOptionRewarder is Ownable, IArkenOptionRewarder {
    using PRBMathUD60x18 for uint256;

    address public immutable arken;

    address public immutable optionNFT;

    uint256 public totalRewardArken;

    uint256 public rewardedArken;

    mapping(address => RewardConfiguration[]) private _configurations;

    mapping(uint256 => bool) public usedPositionToken;

    constructor(address arken_, address nft_, uint256 totalRewardArken_) {
        arken = arken_;
        optionNFT = nft_;
        totalRewardArken = totalRewardArken_;
    }

    function setTotalRewardArken(uint256 totalRewardArken_) external onlyOwner {
        if (totalRewardArken_ < rewardedArken) {
            revert InsufficientTotalReward({
                totalRewardArken: totalRewardArken_,
                rewardedArken: rewardedArken
            });
        }
        totalRewardArken = totalRewardArken_;
        emit SetTotalRewardArken(totalRewardArken_, msg.sender);
    }

    function setConfiguration(
        address pair,
        RewardConfiguration[] memory configs
    ) external onlyOwner {
        delete _configurations[pair];
        for (uint i = 0; i < configs.length; i++) {
            _configurations[pair].push(configs[i]);
        }
        emit SetConfiguration(pair, msg.sender, configs);
    }

    function deleteConfiguration(address pair) external onlyOwner {
        delete _configurations[pair];
        emit DeleteConfiguration(pair, msg.sender);
    }

    function configuration(
        address pair,
        uint256 idx
    ) public view returns (RewardConfiguration memory config) {
        config = _configurations[pair][idx];
    }

    function configurations(
        address pair
    ) public view returns (RewardConfiguration[] memory) {
        return _configurations[pair];
    }

    function rewardLongTerm(
        address to,
        address pair,
        uint256 positionTokenId,
        bytes calldata data
    ) external returns (uint256[] memory tokenIds) {
        if (usedPositionToken[positionTokenId]) {
            revert PositionRewarded({positionTokenId: positionTokenId});
        }
        usedPositionToken[positionTokenId] = true;
        RewardConfiguration[] memory configs = configurations(pair);
        if (configs.length == 0) {
            revert NotSupportedPair({pair: pair});
        }
        RewardLongTermData memory longtermData = abi.decode(
            data,
            (RewardLongTermData)
        );
        if (
            IArkenPairLongTerm(pair).ownerOf(positionTokenId) != address(this)
        ) {
            revert NoPosition();
        }
        uint256 len = longtermData.exerciseAmountMins.length;
        if (len != configs.length) {
            revert InvalidExerciseAmountMinLength({
                length: len,
                expectedLength: configs.length
            });
        }
        tokenIds = new uint256[](len);
        for (uint i = 0; i < len; i++) {
            (tokenIds[i], ) = _rewardLongTermByConfig(
                to,
                pair,
                positionTokenId,
                longtermData.exerciseAmountMins[i],
                configs[i]
            );
        }
        IArkenPairLongTerm(pair).transferFrom(
            address(this),
            to,
            positionTokenId
        );
    }

    function _rewardLongTermByConfig(
        address to,
        address pair,
        uint256 positionTokenId,
        uint256 exerciseAmountMin,
        RewardConfiguration memory config
    ) internal returns (uint256 tokenId, uint256 exerciseAmount) {
        exerciseAmount = _calculateExerciseAmount(
            pair,
            positionTokenId,
            config
        );
        uint256 _remainingArken = totalRewardArken - rewardedArken;
        if (_remainingArken == 0) {
            revert InsufficientRemainingArken();
        }
        if (exerciseAmount > _remainingArken) {
            exerciseAmount = _remainingArken;
        }
        if (exerciseAmount < exerciseAmountMin) {
            revert InsufficientExerciseAmount({
                amount: exerciseAmount,
                amountMin: exerciseAmountMin
            });
        }
        uint256 positionUnlockedAt = IArkenPairLongTerm(pair).unlockedAt(
            positionTokenId
        );
        uint256 positionMintedAt = IArkenPairLongTerm(pair).mintedAt(
            positionTokenId
        );
        if (config.lockTime > positionUnlockedAt - positionMintedAt) {
            revert InsufficientLockTime({
                lockTime: positionUnlockedAt - positionMintedAt,
                minimumLockTime: config.lockTime
            });
        }
        rewardedArken = rewardedArken + exerciseAmount;
        tokenId = IArkenOptionNFT(optionNFT).mint(
            to,
            IArkenOptionNFT.TokenData({
                unlockedAt: positionMintedAt + config.lockTime,
                expiredAt: positionMintedAt + config.expiredTime,
                unlockPrice: config.unlockPrice,
                exercisePrice: config.exercisePrice,
                exerciseAmount: exerciseAmount,
                optionType: config.optionType
            })
        );
        emit RewardOptionNFT(
            tokenId,
            address(pair),
            positionMintedAt + config.lockTime,
            positionMintedAt + config.expiredTime,
            config.unlockPrice,
            config.exercisePrice,
            exerciseAmount
        );
    }

    function _calculateExerciseAmount(
        address pair,
        uint256 positionTokenId,
        RewardConfiguration memory config
    ) internal view returns (uint256 exerciseAmount) {
        uint256 liquidity = IArkenPairLongTerm(pair).liquidityOf(
            positionTokenId
        );
        exerciseAmount = liquidity.mul(config.exerciseAmountFactor);
    }
}

