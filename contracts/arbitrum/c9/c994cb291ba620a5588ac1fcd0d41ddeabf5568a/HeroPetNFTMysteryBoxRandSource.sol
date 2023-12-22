// SPDX-License-Identifier: MIT
// DreamIdol Contracts (HeroNFTMysteryBox.sol)

pragma solidity ^0.8.0;

import "./MBRandomSourceBase.sol";

import "./HeroNFTCodec.sol";
import "./HeroNFT.sol";

contract HeroPetNFTMysteryBoxRandSource is 
    MBRandomSourceBase
{
    using RandomPoolLib for RandomPoolLib.RandomPool;

    HeroNFT public _heroNFTContract;
    
    constructor(address heroNftAddr)
    {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(MINTER_ROLE, _msgSender());

        _heroNFTContract = HeroNFT(heroNftAddr);
    }

    function randomAndMint(uint256 r, uint32 mysteryTp, address to) virtual override external 
        returns(MBContentMinter1155Info[] memory sfts, MBContentMinterNftInfo[] memory nfts)
    {
        require(hasRole(MINTER_ROLE, _msgSender()), "ownership error");

        uint32[] storage poolIDArray = _mbRandomSets[mysteryTp];

        require(poolIDArray.length == 10, "mb type config wrong");

        HeroNFTDataBase memory baseData = _getSingleRandHero(r, poolIDArray);

        // mint 
        uint256 newId = _heroNFTContract.mint(to, baseData);

        nfts = new MBContentMinterNftInfo[](1); // 1 nft
        sfts = new MBContentMinter1155Info[](0); // no sft

        nfts[0] = MBContentMinterNftInfo({
            addr : address(_heroNFTContract),
            tokenIds : new uint256[](1)
        });
        nfts[0].tokenIds[0] = newId;
    }

    function _getSingleRandHero(
        uint256 r,
        uint32[] storage poolIDArray
    ) internal view returns (HeroNFTDataBase memory baseData)
    {
        uint32 index = 0;
        
        NFTRandPool storage pool = _randPools[poolIDArray[0]]; // index 0 : petId rand (1-5)
        require(pool.exist, "job pool not exist");
        uint8 petId = uint8(pool.randPool.random(r));

        r = _rand.nextRand(++index, r);
        pool = _randPools[poolIDArray[1]]; // index 1 : avatar slot 1 rand (1-10)
        require(pool.exist, "grade pool not exist");
        uint8 avatar_slot_1_2 = uint8(pool.randPool.random(r)) << 4;
        
        r = _rand.nextRand(++index, r);
        pool = _randPools[poolIDArray[2]]; // index 2 : avatar slot 2 rand (1-10)
        require(pool.exist, "grade pool not exist");
        avatar_slot_1_2 |= uint8(pool.randPool.random(r));
        
        r = _rand.nextRand(++index, r);
        pool = _randPools[poolIDArray[3]]; // index 3 : avatar slot 3 rand (1-10)
        require(pool.exist, "grade pool not exist");
        uint8 avatar_slot_3_4 = uint8(pool.randPool.random(r)) << 4;
        
        r = _rand.nextRand(++index, r);
        pool = _randPools[poolIDArray[4]]; // index 4 : avatar slot 4 rand (1-10)
        require(pool.exist, "grade pool not exist");
        avatar_slot_3_4 |= uint8(pool.randPool.random(r));
        
        r = _rand.nextRand(++index, r);
        pool = _randPools[poolIDArray[5]]; // index 5 : avatar slot 5 rand (1-10)
        require(pool.exist, "grade pool not exist");
        uint8 avatar_slot_5_6 = uint8(pool.randPool.random(r)) << 4;
        
        r = _rand.nextRand(++index, r);
        pool = _randPools[poolIDArray[6]]; // index 6 : avatar slot 6 rand (1-10)
        require(pool.exist, "grade pool not exist");
        avatar_slot_5_6 |= uint8(pool.randPool.random(r));

        pool = _randPools[poolIDArray[7]]; // index 7 : mineAttr rand
        r = _rand.nextRand(++index, r);
        require(pool.exist, "mineAttr pool not exist");
        uint16 mineAttr = uint8(pool.randPool.random(r));

        pool = _randPools[poolIDArray[8]]; // index 8 : battleAttr rand
        r = _rand.nextRand(++index, r);
        require(pool.exist, "battleAttr pool not exist");
        uint16 battleAttr = uint8(pool.randPool.random(r));

        HeroPetNFTFixedData_V1 memory fdata = HeroPetNFTFixedData_V1({
            petId : petId,
            avatar_slot_1_2 : avatar_slot_1_2,
            avatar_slot_3_4 : avatar_slot_3_4,
            avatar_slot_5_6 : avatar_slot_5_6,
            minerAttr : mineAttr,
            battleAttr : battleAttr
        });

        HeroPetNFTWriteableData_V1 memory wdata = HeroPetNFTWriteableData_V1({
            level:1
        });

        IHeroNFTCodec_V1 codec = IHeroNFTCodec_V1(_heroNFTContract.getCodec());
        baseData = codec.fromHeroPetNftFixedAnWriteableData(fdata, wdata);
        baseData.mintType = uint8(poolIDArray[9]); // index 9 : mint type
    }

    function batchRandomAndMint(uint256 r, uint32 mysteryTp, address to, uint8 batchCount) virtual override external 
        returns(MBContentMinter1155Info[] memory sfts, MBContentMinterNftInfo[] memory nfts)
    {
        require(hasRole(MINTER_ROLE, _msgSender()), "ownership error");

        uint32[] storage poolIDArray = _mbRandomSets[mysteryTp];

        require(poolIDArray.length == 10, "mb type config wrong");

        nfts = new MBContentMinterNftInfo[](1); // 1 nft
        sfts = new MBContentMinter1155Info[](0); // no sft record

        nfts[0] = MBContentMinterNftInfo({
            addr : address(_heroNFTContract),
            tokenIds : new uint256[](batchCount)
        });

        for(uint8 i=0; i< batchCount; ++i)
        {
            r = _rand.nextRand(i, r);
            HeroNFTDataBase memory baseData = _getSingleRandHero(r, poolIDArray);

            // mint 
            uint256 newId = _heroNFTContract.mint(to, baseData);

            nfts[0].tokenIds[i] = newId;
        }
    }
}
