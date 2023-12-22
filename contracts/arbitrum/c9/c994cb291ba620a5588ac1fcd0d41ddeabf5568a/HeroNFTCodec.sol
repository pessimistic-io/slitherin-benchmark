// SPDX-License-Identifier: MIT
// Metaline Contracts (HeroNFTCodec.sol)

pragma solidity ^0.8.0;

/**
 * @dev base struct of hero nft data
 */
struct HeroNFTDataBase
{
    uint8 mintType; // = 0 normal mint, = 1: genesis mint
    uint16 nftType; // = 1: hero nft, = 2: pet nft
    uint232 fixedData;
    uint256 writeableData;
}

/**
 * @dev hero fixed nft data version 1
 */
struct HeroNFTFixedData_V1 {
    uint8 job;
    uint8 grade;

    uint32 minerAttr;
    uint32 battleAttr;
}

/**
 * @dev hero pet fixed nft data version 1
 */
struct HeroPetNFTFixedData_V1 {
    uint8 petId;
    uint8 avatar_slot_1_2;
    uint8 avatar_slot_3_4;
    uint8 avatar_slot_5_6;

    uint32 minerAttr;
    uint32 battleAttr;
}

/**
 * @dev hero writeable nft data version 1
 */
struct HeroNFTWriteableData_V1 {
    uint8 starLevel;
    uint16 level;
}

/**
 * @dev hero writeable nft data version 1
 */
struct HeroPetNFTWriteableData_V1 {
    uint16 level;
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
    * @dev encode HeroNFTPetFixedData to HeroNFTDataBase
    * @param data input data of HeroPetNFTFixedData_V1
    * @return basedata output data of HeroNFTDataBase
    */
    function fromHeroPetNftFixedData(HeroPetNFTFixedData_V1 memory data) external pure returns (HeroNFTDataBase memory basedata);

    /**
    * @dev encode HeroNFTFixedData to HeroNFTDataBase
    * @param fdata input data of HeroNFTFixedData_V1
    * @param wdata input data of HeroNFTWriteableData_V1
    * @return basedata output data of HeroNFTDataBase
    */
    function fromHeroNftFixedAnWriteableData(HeroNFTFixedData_V1 memory fdata, HeroNFTWriteableData_V1 memory wdata) external pure returns (HeroNFTDataBase memory basedata);

    /**
    * @dev encode HeroNFTFixedData to HeroNFTDataBase
    * @param fdata input data of HeroPetNFTFixedData_V1
    * @param wdata input data of HeroPetNFTWriteableData_V1
    * @return basedata output data of HeroNFTDataBase
    */
    function fromHeroPetNftFixedAnWriteableData(HeroPetNFTFixedData_V1 memory fdata, HeroPetNFTWriteableData_V1 memory wdata) external pure returns (HeroNFTDataBase memory basedata);

    /**
    * @dev decode HeroNFTData from HeroNFTDataBase
    * @param data input data of HeroNFTDataBase
    * @return hndata output data of HeroNFTFixedData_V1
    */
    function getHeroNftFixedData(HeroNFTDataBase memory data) external pure returns(HeroNFTFixedData_V1 memory hndata);

    /**
    * @dev decode HeroPetNFTData from HeroNFTDataBase
    * @param data input data of HeroNFTDataBase
    * @return hndata output data of HeroPetNFTFixedData_V1
    */
    function getHeroPetNftFixedData(HeroNFTDataBase memory data) external pure returns(HeroPetNFTFixedData_V1 memory hndata);

    /**
    * @dev encode HeroNFTData to HeroNFTDataBase writeable
    * @param hndata input data of HeroNFTWriteableData_V1
    * @return wdata output data of HeroNFTDataBase writeable
    */
    function toHeroNftWriteableData(HeroNFTWriteableData_V1 memory hndata) external pure returns(uint256 wdata);
    
    /**
    * @dev encode HeroPetNFTData to HeroNFTDataBase writeable
    * @param hndata input data of HeroPetNFTWriteableData_V1
    * @return wdata output data of HeroNFTDataBase writeable
    */
    function toHeroPetNftWriteableData(HeroPetNFTWriteableData_V1 memory hndata) external pure returns(uint256 wdata);

    /**
    * @dev decode HeroNFTData from HeroNFTDataBase
    * @param data input data of HeroNFTDataBase
    * @return hndata output data of HeroNFTWriteableData_V1
    */
    function getHeroNftWriteableData(HeroNFTDataBase memory data) external pure returns(HeroNFTWriteableData_V1 memory hndata);
    
    /**
    * @dev decode HeroPetNFTData from HeroNFTDataBase
    * @param data input data of HeroNFTDataBase
    * @return hndata output data of HeroPetNFTWriteableData_V1
    */
    function getHeroPetNftWriteableData(HeroNFTDataBase memory data) external pure returns(HeroPetNFTWriteableData_V1 memory hndata);

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
            uint232(data.job) |
            (uint232(data.grade) << 8) |
            (uint232(data.minerAttr) << (8 + 8)) |
            (uint232(data.battleAttr) << (8 + 8 + 32));

        basedata.nftType = 1;
        //basedata.mintType = 0;
        //basedata.writeableData = 0;
    }
    
    function fromHeroPetNftFixedData(HeroPetNFTFixedData_V1 memory data)
        external
        pure
        override
        returns (HeroNFTDataBase memory basedata)
    {
        basedata.fixedData =
            uint232(data.petId) |
            (uint232(data.avatar_slot_1_2) << 8) |
            (uint232(data.avatar_slot_3_4) << (8 + 8)) |
            (uint232(data.avatar_slot_5_6) << (8 + 8 + 8)) |
            (uint232(data.minerAttr) << (8 + 8 + 8 + 8)) |
            (uint232(data.battleAttr) << (8 + 8 + 8 + 8 + 32));

        basedata.nftType = 2;
        //basedata.mintType = 0;
        //basedata.writeableData = 0;
    }

    function fromHeroNftFixedAnWriteableData(HeroNFTFixedData_V1 memory fdata, HeroNFTWriteableData_V1 memory wdata) 
        external 
        pure 
        override 
        returns (HeroNFTDataBase memory basedata)
    {
        basedata.fixedData =
            uint232(fdata.job) |
            (uint232(fdata.grade) << 8) |
            (uint232(fdata.minerAttr) << (8 + 8)) |
            (uint232(fdata.battleAttr) << (8 + 8 + 32));

        basedata.writeableData = 
            (uint256(wdata.starLevel)) |
            (uint256(wdata.level << 8));
            
        //basedata.mintType = 0;
        basedata.nftType = 1;
    }
    
    function fromHeroPetNftFixedAnWriteableData(HeroPetNFTFixedData_V1 memory fdata, HeroPetNFTWriteableData_V1 memory wdata) 
        external 
        pure
        override 
        returns (HeroNFTDataBase memory basedata) 
    {
        basedata.fixedData =
            uint232(fdata.petId) |
            (uint232(fdata.avatar_slot_1_2) << 8) |
            (uint232(fdata.avatar_slot_3_4) << (8 + 8)) |
            (uint232(fdata.avatar_slot_5_6) << (8 + 8 + 8)) |
            (uint232(fdata.minerAttr) << (8 + 8 + 8 + 8)) |
            (uint232(fdata.battleAttr) << (8 + 8 + 8 + 8 + 32));

        basedata.writeableData = 
            (uint256(wdata.level));
            
        //basedata.mintType = 0;
        basedata.nftType = 2;
    }

    function getHeroNftFixedData(HeroNFTDataBase memory data)
        external
        pure
        override
        returns (HeroNFTFixedData_V1 memory hndata)
    {
        hndata.job = uint8(data.fixedData & 0xff);
        hndata.grade = uint8((data.fixedData >> 8) & 0xff);
        hndata.minerAttr = uint32((data.fixedData >> (8 + 8)) & 0xffffffff);
        hndata.battleAttr = uint32((data.fixedData >> (8 + 8 + 32)) & 0xffffffff);
    }

    function getHeroPetNftFixedData(HeroNFTDataBase memory data)
        external
        pure
        override
        returns (HeroPetNFTFixedData_V1 memory hndata)
    {
        hndata.petId = uint8(data.fixedData & 0xff);
        hndata.avatar_slot_1_2 = uint8((data.fixedData >> 8) & 0xff);
        hndata.avatar_slot_3_4 = uint8((data.fixedData >> (8 + 8)) & 0xff);
        hndata.avatar_slot_5_6 = uint8((data.fixedData >> (8 + 8 + 8)) & 0xff);
        hndata.minerAttr = uint32((data.fixedData >> (8 + 8 + 8 + 8)) & 0xffffffff);
        hndata.battleAttr = uint16((data.fixedData >> (8 + 8 + 8 + 8 + 32)) & 0xffffffff);
    }
    
    function toHeroNftWriteableData(HeroNFTWriteableData_V1 memory hndata) 
        external 
        pure 
        override 
        returns(uint256 wdata) 
    {
        return
            (uint256(hndata.starLevel)) |
            (uint256(hndata.level << 8));
    }
    
    function toHeroPetNftWriteableData(HeroPetNFTWriteableData_V1 memory hndata) 
        external 
        pure 
        override 
        returns(uint256 wdata) 
    {
        return
            (uint256(hndata.level));
    }

    function getHeroNftWriteableData(HeroNFTDataBase memory data) 
        external 
        pure 
        override 
        returns(HeroNFTWriteableData_V1 memory hndata)
    {
        hndata.starLevel = uint8(data.writeableData & 0xff);
        hndata.level = uint16((data.writeableData >> 8) & 0xffff);
    }
    
    function getHeroPetNftWriteableData(HeroNFTDataBase memory data) 
        external 
        pure 
        override 
        returns(HeroPetNFTWriteableData_V1 memory hndata)
    {
        hndata.level = uint16(data.writeableData & 0xffff);
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
