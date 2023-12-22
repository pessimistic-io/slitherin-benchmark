// SPDX-License-Identifier: MIT
// Mateline Contracts (HeroNFTCodec.sol)

pragma solidity ^0.8.0;

/**
 * @dev base struct of hero nft data
 */
struct HeroNFTDataBase
{
    uint256 fixedData;
    uint256 writeableData;
}

/**
 * @dev hero fixed nft data version 1
 */
struct HeroNFTFixedData_V1 {
    uint8 job;
    uint8 grade;

    uint16 minerAttr;
    uint16 battleAttr;
}

/**
 * @dev hero writeable nft data version 1
 */
struct HeroNFTWriteableData_V1 {
    uint8 starLevel;
    uint16 level;
    uint64 exp;
}


/**
 * @dev hero nft data codec interface
 */
interface IHeroNFTCodec_V1 {

    /**
    * @dev encode HeroNFTFixedData to HeroNFTDataBase
    * @param data input data of HeroNFTFixedData_V1
    * @return basedata output data of HeroNFTDataBase
    */
    function fromHeroNftFixedData(HeroNFTFixedData_V1 memory data) external pure returns (HeroNFTDataBase memory basedata);

    /**
    * @dev encode HeroNFTFixedData to HeroNFTDataBase
    * @param fdata input data of HeroNFTFixedData_V1
    * @param wdata input data of HeroNFTWriteableData_V1
    * @return basedata output data of HeroNFTDataBase
    */
    function fromHeroNftFixedAnWriteableData(HeroNFTFixedData_V1 memory fdata, HeroNFTWriteableData_V1 memory wdata) external pure returns (HeroNFTDataBase memory basedata);

    /**
    * @dev decode HeroNFTData from HeroNFTDataBase
    * @param data input data of HeroNFTDataBase
    * @return hndata output data of HeroNFTFixedData_V1
    */
    function getHeroNftFixedData(HeroNFTDataBase memory data) external pure returns(HeroNFTFixedData_V1 memory hndata);

    /**
    * @dev decode HeroNFTData from HeroNFTDataBase
    * @param data input data of HeroNFTDataBase
    * @return hndata output data of HeroNFTWriteableData_V1
    */
    function getHeroNftWriteableData(HeroNFTDataBase memory data) external pure returns(HeroNFTWriteableData_V1 memory hndata);

    /**
    * @dev get character id from HeroNFTDataBase
    * @param data input data of HeroNFTDataBase
    * @return characterId character id
    */
    function getCharacterId(HeroNFTDataBase memory data) external pure returns (uint16 characterId);
}

/**
 * @dev hero nft data codec v1 implement
 */
contract HeroNFTCodec_V1 is IHeroNFTCodec_V1 {

    function fromHeroNftFixedData(HeroNFTFixedData_V1 memory data)
        external
        pure
        override
        returns (HeroNFTDataBase memory basedata)
    {
        basedata.fixedData =
            uint256(data.job) |
            (uint256(data.grade) << 8) |
            (uint256(data.minerAttr) << (8 + 8)) |
            (uint256(data.battleAttr) << (8 + 8 + 16));

        basedata.writeableData = 0;
    }

    function fromHeroNftFixedAnWriteableData(HeroNFTFixedData_V1 memory fdata, HeroNFTWriteableData_V1 memory wdata) 
        external 
        pure 
        override 
        returns (HeroNFTDataBase memory basedata)
    {
        basedata.fixedData =
            uint256(fdata.job) |
            (uint256(fdata.grade) << 8) |
            (uint256(fdata.minerAttr) << (8 + 8)) |
            (uint256(fdata.battleAttr) << (8 + 8 + 16));

        basedata.writeableData = 
            (uint256(wdata.starLevel)) |
            (uint256(wdata.level << 8)) |
            (uint256(wdata.exp << (8 + 16)));
    }

    function getHeroNftFixedData(HeroNFTDataBase memory data)
        external
        pure
        override
        returns (HeroNFTFixedData_V1 memory hndata)
    {
        hndata.job = uint8(data.fixedData & 0xff);
        hndata.grade = uint8((data.fixedData >> 8) & 0xff);
        hndata.minerAttr = uint16((data.fixedData >> (8 + 8)) & 0xffff);
        hndata.battleAttr = uint16((data.fixedData >> (8 + 8 + 16)) & 0xffff);
    }

    function getHeroNftWriteableData(HeroNFTDataBase memory data) 
        external 
        pure 
        override 
        returns(HeroNFTWriteableData_V1 memory hndata)
    {
        hndata.starLevel = uint8(data.writeableData & 0xff);
        hndata.level = uint16((data.writeableData >> 8) & 0xffff);
        hndata.exp = uint64((data.writeableData >> 8 + 16) & 0xffffffffffffffff);
    }

    function getCharacterId(HeroNFTDataBase memory data) 
        external 
        pure 
        override
        returns (uint16 characterId) 
    {
        return uint16(data.fixedData & 0xffff); // job << 8 | grade;
    }
}
