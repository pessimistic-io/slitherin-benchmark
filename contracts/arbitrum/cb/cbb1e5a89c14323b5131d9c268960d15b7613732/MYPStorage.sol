//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./MYPAssetsA.sol";
import "./MYPAssetsB.sol";
import "./MYPAssetsC.sol";

import { MYPart } from "./MYP.sol";
import { Constants } from "./MYPConstants.sol";

/**
................................................
................................................
................................................
................................................
...................';::::::;'.';'...............
.............';'.':kNWWWWWWNkcod;...............
.............oXkckNWMMMMMMMMWNkc'.';'...........
.........'::ckWWWWMMMMMMMMMMMMWNkcoxo:'.........
.........;xKWWMMMMWXKNMMMMMMMMMMWNklkXo.........
.........'cOWMMMMN0kxk0XWWXK0KNWMMWWKk:.........
.......':okKWMMMWOldkdlkNNkcccd0NMMWOc'.........
.......;dolOWMWX0d:;::ckXXkc:;;:lkKWKko:'.......
.......':okKWN0dc,.',;:dOOkd:.''..lNOlod:.......
.....':kNklONx;;:,.';:::ccdkc.',. lWMNo.........
.....:xkOKWWWl..:::::::::::c:::;. lWMWk:'.......
.........dWMWl .:::::::;;;;:::::. lNXOkx;.......
. .....':okkk; .;::::::,'',:::::. ;xdc'.........
.......:d:...  .;::::;,,,,,,;:::.  .:d:.........
.. ..........  .';:::,'....',:;'.  .............
..............   .,,,;::::::;'.    .............
..............    .  .''''''.   ................
..............   ....          .................
..............   .;,....    . ..................
..............   .;:::;.    ....................

               Made with <3 from
             @author @goldendilemma

    TODO: Remove "Hacking" background before deploy

*/

contract MYPStorage {

  IMYPAssetStorage[3] assets;

  constructor() {
    assets[0] = new MYPAssetsA();
    assets[1] = new MYPAssetsB();
    assets[2] = new MYPAssetsC();
  }

  function getAssetIndexFromIndex (uint index)
  private pure
  returns (uint) {
    if (index < 44) return 0;
		if (index < 88) return 1;
		if (index < 132) return 2;
    revert();
  }

  function getOffsetFromIndex (uint index)
  private pure
  returns (uint) {
    if (index < 44) return 0;
		if (index < 88) return 44;
		if (index < 132) return 88;
    revert();
  }

  function getGenderName (uint8 index) 
  external pure
  returns (string memory) {
    return ['Male', 'Female', 'Non-Binary'][index];
  }

  function getDirectionName (uint8 index) 
  external pure
  returns (string memory) {
    return ['Alternate', 'Right', 'Left'][index];
  }

  function getCategoryNameByIndex (uint index) 
  external pure 
  returns (string memory) {
    return ['Background','Type Secret','Head','Skin','Ear','Hair','Neck','Nose','Mouth','Beard','Smoke','Eyes','Glasses'][index];
  }

  function getColorByIndex(uint8 index) 
  internal pure 
  returns (string memory) { 
    return ['DBB180','000000','FFFFFF','C8FBFB','7DA269','352410','856F56','EAD9D9','FF8EBE','D60000','FB4747','2858B1','1C1A00','534C00','80DBDA','F0F0F0','328DFD','AD2160','C77514','C6C6C6','FFD926','FF0000','1A43C8','FFF68E','710CC7','28B143','E22626','CA4E11','A66E2C','E65700','2D6B62','51360C','229000','005580','FFC926','5F1D09','68461F','794B11','692F08','740000','B90000','0060C3','E4EB17','595959','4C4C4C','743939','26314A','A39797','ACACAC','0000FF','FF00FF','00FF00','FEF433','9A59CF','AE8B61','713F1D'][index]; 
  }

  function validate (uint8 typeIndex, uint16 attrIndex, uint8 catIndex) 
  external pure {
  uint8 attrType = [uint8(2),1,0,1,0,2,1,0,0,0,0,1,0,1,1,0,1,0,1,0,1,0,1,1,0,1,1,1,0,1,0,1,0,1,0,1,1,0,1,0,1,0,1,1,1,1,1,1,0,1,1,1,1,0,1,0,0,0,0,0,1,0,0,1,0,0,0,0,0,0,0,1,0,1,0,1,0,0,0,1,0,1,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,1,0,1,0,1,0,1,0,0,0,0,1,0,1,1,0,1,0,1,0,1,0,1,0,1,0,1,0,1,0,0,1,0][attrIndex];
  uint8 attrCatIndex = [uint8(0),0,0,0,0,1,2,2,2,2,2,2,2,3,3,3,3,3,3,3,4,4,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,6,6,6,6,7,7,7,7,7,7,8,8,8,8,8,8,9,9,9,9,9,9,9,9,9,9,9,9,10,10,10,10,10,10,11,11,11,11,11,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12][attrIndex];
  uint16 catLength = [uint16(5),1,7,7,2,49,4,6,6,12,6,5,22][attrCatIndex];
  uint16 catIndexStart = [uint16(0),5,6,13,20,22,71,75,81,87,99,105,110][attrCatIndex];
  bool isRemovable = [true,true,false,true,true,true,true,false,false,true,true,false,true][attrCatIndex];
    if (attrIndex == Constants.NONE) {
      require(isRemovable, "MALFORMED_PUNK_4");
    } else {
      require(attrType == typeIndex || attrType == 2, "MALFORMED_PUNK_1");
      require(catIndexStart < catIndexStart + catLength, "MALFORMED_PUNK_2");
      require(catIndex == attrCatIndex, "MALFORMED_PUNK_3");
    }
  }

  function fillIndexToFills (
  uint8[] memory fillIndexes,
  AssetData memory asset
  ) 
  private pure
  returns (string[8] memory) 
  {
    string[8] memory out; // NOTE: MAX n in string[n] fills per attribute.
    for (uint i = 0; i < asset.fillLength; i++) {
      out[i] = getColorByIndex(fillIndexes[i]);
    }
    return out;
  }

  function getStoreFromIndex (uint attrIndex) private view returns (IMYPAssetStorage) { return assets[getAssetIndexFromIndex(attrIndex)]; }

  function getFillLength (uint16 attrIndex) 
  external view 
  returns (uint)
  {
    IMYPAssetStorage store = getStoreFromIndex(attrIndex);
    AssetData memory asset = store.getAssetFromIndex(attrIndex - getOffsetFromIndex(attrIndex));
    return asset.fillLength;
  }

  function getAsset(uint16 attrIndex, uint8[] calldata fillIndexes) 
  external view 
  returns (MYPart memory) 
  {
    IMYPAssetStorage store = getStoreFromIndex(attrIndex);
    AssetData memory asset = store.getAssetFromIndex(attrIndex - getOffsetFromIndex(attrIndex));
    return MYPart({
      fills: fillIndexToFills(fillIndexes, asset),
      asset: asset
    });
  }

}
