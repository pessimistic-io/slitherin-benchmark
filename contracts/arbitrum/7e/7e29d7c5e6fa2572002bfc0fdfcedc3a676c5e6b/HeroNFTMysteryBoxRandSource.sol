// SPDX-License-Identifier: MIT
// DreamIdol Contracts (HeroNFTMysteryBox.sol)

pragma solidity ^0.8.0;

import "./MBRandomSourceBase.sol";

import "./HeroNFTCodec.sol";
import "./HeroNFT.sol";

contract HeroNFTMysteryBoxRandSource is 
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

        require(poolIDArray.length == 33, "mb type config wrong");

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
        
        NFTRandPool storage pool = _randPools[poolIDArray[0]]; // index 0 : job rand (1-15)
        require(pool.exist, "job pool not exist");
        uint8 job = uint8(pool.randPool.random(r));

        r = _rand.nextRand(++index, r);
        pool = _randPools[poolIDArray[1]]; // index 1 : grade rand (1-10)
        require(pool.exist, "grade pool not exist");
        uint8 grade = uint8(pool.randPool.random(r));

        if(job <= 2){
            pool = _randPools[poolIDArray[1 + grade]]; // index 2-11 : job(1-2) mineAttr rand by grade 
        }
        else{
            pool = _randPools[poolIDArray[11 + grade]]; // index 12-21 : job(3-15) mineAttr rand by grade
        }
        r = _rand.nextRand(++index, r);
        require(pool.exist, "mineAttr pool not exist");
        uint16 mineAttr = uint8(pool.randPool.random(r));

        pool = _randPools[poolIDArray[21 + grade]]; // index 22-31 : battleAttr rand by grade
        r = _rand.nextRand(++index, r);
        require(pool.exist, "battleAttr pool not exist");
        uint16 battleAttr = uint8(pool.randPool.random(r));

        HeroNFTFixedData_V1 memory fdata = HeroNFTFixedData_V1({
            job : job,
            grade : grade,
            minerAttr : mineAttr,
            battleAttr : battleAttr
        });

        HeroNFTWriteableData_V1 memory wdata = HeroNFTWriteableData_V1({
            starLevel: 0,
            level : 1
        });

        IHeroNFTCodec_V1 codec = IHeroNFTCodec_V1(_heroNFTContract.getCodec());
        baseData = codec.fromHeroNftFixedAnWriteableData(fdata, wdata);
        baseData.mintType = uint8(poolIDArray[32]); // index 32 : mint type
    }

    function batchRandomAndMint(uint256 r, uint32 mysteryTp, address to, uint8 batchCount) virtual override external 
        returns(MBContentMinter1155Info[] memory sfts, MBContentMinterNftInfo[] memory nfts)
    {
        require(hasRole(MINTER_ROLE, _msgSender()), "ownership error");

        uint32[] storage poolIDArray = _mbRandomSets[mysteryTp];

        require(poolIDArray.length == 33, "mb type config wrong");

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
