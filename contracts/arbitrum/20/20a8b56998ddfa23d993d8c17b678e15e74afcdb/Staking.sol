// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

import "./baseContract.sol";
import "./ILYNKNFT.sol";
import "./IBNFT.sol";
import "./IUser.sol";
import "./IERC20Mintable.sol";
import "./IERC721ReceiverUpgradeable.sol";
import "./IERC721Upgradeable.sol";
// Uncomment this line to use console.log
// import "hardhat/console.sol";

contract Staking is baseContract, IERC721ReceiverUpgradeable {
    mapping(address => MiningPower) public miningPowerOf;
    mapping(address => uint256) public rewardOf;
    mapping(address => uint256) public lastUpdateTimeOf;

    event Stake(address indexed account, uint256 tokenId);
    event UnStake(address indexed account, uint256 tokenId);
    event Claim(address indexed account, uint256 amount);

    struct MiningPower {
        uint256 charisma;
        uint256 dexterity;
    }

    //v2
    event StakeInfo(address indexed account,uint256 nftId,uint256 ca,uint256 va,uint256 ia,uint256 dx);
    event UnStakeInfo(address indexed account,uint256 nftId,uint256 ca,uint256 va,uint256 ia,uint256 dx);

    constructor(address dbAddress) baseContract(dbAddress){

    }

    function __Staking_init() public initializer {
        __baseContract_init();
        __Staking_init_unchained();
    }

    function __Staking_init_unchained() private {
    }

    modifier updateReward(address account) {
        uint256 lastUpdateTime = lastUpdateTimeOf[account];
        lastUpdateTimeOf[account] = block.timestamp;

        uint256 charisma = miningPowerOf[account].charisma;
        uint256 dexterity = miningPowerOf[account].dexterity;
        uint256 rewardRate = _rewardRate(charisma, dexterity);

        rewardOf[account] += rewardRate * (block.timestamp - lastUpdateTime);

        _;
    }

    function claimableOf(address account) external view returns (uint256) {
        uint256 charisma = miningPowerOf[account].charisma;
        uint256 dexterity = miningPowerOf[account].dexterity;
        uint256 rewardRate = _rewardRate(charisma, dexterity);

        return rewardOf[account] + rewardRate * (block.timestamp - lastUpdateTimeOf[account]);
    }

    function stake(uint256 nftId) external updateReward(_msgSender()) {
        require(
            IUser(DBContract(DB_CONTRACT).USER_INFO()).isValidUser(_msgSender()),
                'Staking: not a valid user.'
        );

        uint256 charisma = 0;
        uint256 dexterity = 0;
        address lynkNFTAddress = DBContract(DB_CONTRACT).LYNKNFT();
        address bLYNKNFTAddress = DBContract(DB_CONTRACT).STAKING_LYNKNFT();

        IERC721Upgradeable(lynkNFTAddress).safeTransferFrom(_msgSender(), address(this), nftId);
        IERC721Upgradeable(lynkNFTAddress).approve(bLYNKNFTAddress, nftId);
        IBNFT(bLYNKNFTAddress).mint(_msgSender(), nftId);

        emit Stake(_msgSender(), nftId);

        uint256[] memory nftInfo = ILYNKNFT(lynkNFTAddress).nftInfoOf(nftId);
        charisma += nftInfo[uint256(ILYNKNFT.Attribute.charisma)];
        dexterity += nftInfo[uint256(ILYNKNFT.Attribute.dexterity)];

        miningPowerOf[_msgSender()].charisma += charisma;
        miningPowerOf[_msgSender()].dexterity += dexterity;

        //v2
        uint256 vitality = 0;
        uint256 intellect = 0;
        vitality += nftInfo[uint256(ILYNKNFT.Attribute.vitality)];
        intellect += nftInfo[uint256(ILYNKNFT.Attribute.intellect)];
        emit StakeInfo(_msgSender(),nftId,charisma,vitality,intellect,dexterity);

        IUser(DBContract(DB_CONTRACT).USER_INFO()).hookByStake(nftId);
    }

    function unstake(uint256 nftId) external updateReward(_msgSender()) {
        address lynkNFTAddress = DBContract(DB_CONTRACT).LYNKNFT();
        address bLYNKNFTAddress = DBContract(DB_CONTRACT).STAKING_LYNKNFT();

        require(IERC721Upgradeable(bLYNKNFTAddress).ownerOf(nftId) == _msgSender(), 'Staking: not the owner.');

        IBNFT(bLYNKNFTAddress).burn(nftId);
        IERC721Upgradeable(lynkNFTAddress).safeTransferFrom(address(this), _msgSender(), nftId);

        emit UnStake(_msgSender(), nftId);

        uint256[] memory nftInfo = ILYNKNFT(lynkNFTAddress).nftInfoOf(nftId);
        uint256 charisma = nftInfo[uint256(ILYNKNFT.Attribute.charisma)];
        uint256 dexterity = nftInfo[uint256(ILYNKNFT.Attribute.dexterity)];

        //v2
        uint256 vitality = 0;
        uint256 intellect = 0;
        vitality += nftInfo[uint256(ILYNKNFT.Attribute.vitality)];
        intellect += nftInfo[uint256(ILYNKNFT.Attribute.intellect)];
        emit UnStakeInfo(_msgSender(),nftId,charisma,vitality,intellect,dexterity);

        miningPowerOf[_msgSender()].charisma -= charisma;
        miningPowerOf[_msgSender()].dexterity -= dexterity;

        IUser(DBContract(DB_CONTRACT).USER_INFO()).hookByUnStake(nftId);

        // claim reward if the last NFT is claiming.
        if (IERC721Upgradeable(bLYNKNFTAddress).balanceOf(_msgSender()) == 0 && rewardOf[_msgSender()] > 0) {
            _claimReward();
        }
    }

    function claimReward() external updateReward(_msgSender()) {
        _claimReward();
    }

    function onERC721Received(address, address, uint256, bytes calldata) external override pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function _claimReward() private {
        uint256 claimable = rewardOf[_msgSender()];
        require(claimable > 0, 'Staking: cannot claim 0.');

        rewardOf[_msgSender()] = 0;
        IERC20Mintable(DBContract(DB_CONTRACT).LRT_TOKEN()).mint(_msgSender(), claimable);

        emit Claim(_msgSender(), claimable);

        IUser(DBContract(DB_CONTRACT).USER_INFO()).hookByClaimReward(_msgSender(), claimable);
    }

    function _rewardRate(uint256 charisma, uint256 dexterity) private pure returns (uint256) {
        uint256 rewardPerDay = ((0.007 ether) * charisma) + ((0.005 ether) * charisma * dexterity / 100);

        return rewardPerDay / 1 days;
    }

}

