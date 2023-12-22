//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";
import { Strings } from "./Strings.sol";

import "./MYPStorage.sol";

import { MYPunk, MYPart, UserPunk } from "./MYP.sol";
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

*/

contract MYPAPI is Ownable {

  MYPStorage public assets;

  modifier requireAssets() {
    require(address(assets) != address(0), "ASSETS_NOT_INIT");
    _;
  }

  function setAssetContract (address assetContract) 
  public onlyOwner {
    assets = MYPStorage(assetContract);
  }

  function getPunkId(
    uint16[] memory attributeIndexes,
    uint8[][] memory fillIndexes
  ) 
    external view 
    returns (bytes32) 
  {
    uint fillLength;
    bytes memory attrFillHash;
    for (uint8 i = 0; i < Constants.N_CATEGORY; i++) {
      if (i == Constants.BACKGROUND_INDEX || i == Constants.TYPE_INDEX) continue;
      attrFillHash = abi.encodePacked(attrFillHash, attributeIndexes[i]);
      fillLength = assets.getFillLength(attributeIndexes[i]);
      for (uint8 j = 0; j < fillLength; j++) {
        attrFillHash = abi.encodePacked(attrFillHash, fillIndexes[i][j]);
      }
    }
    return keccak256(abi.encodePacked(attrFillHash));
  }

  function getSVGForPart(MYPart memory part)
  private pure
  returns (string memory) {
    string memory svg = '';
    for (uint i = 0; i < part.asset.length; i++) {
      svg = string(abi.encodePacked(
        svg, 
        part.asset.parts[i],
        i < part.asset.fillLength
          ? string(abi.encodePacked('#', part.fills[i]))
          : '',
        '" />'
      ));
    }
    return svg;
  }

  function getJsonProperty (
    string memory key, 
    string memory value, 
    bool appendComma
  ) 
  private pure 
  returns (string memory) 
  {
    return string(abi.encodePacked(
        '"', key, '":', '"', value, '"',
        appendComma ? ',' : ''
      ));
  }

  function shouldRender (uint16 attrIndex) private pure returns (bool) {
    return (
      attrIndex != Constants.NONE || 
      attrIndex == Constants.ATTR_CLOWN_NOSE_X || 
      attrIndex == Constants.ATTR_CLOWN_NOSE_Y
    );
  }

  function validatePunk(
    uint8 genderIndex,
    uint8 typeIndex,
    uint16[] calldata attributes,
    uint8[][] calldata fillIndexes
  )
    public view
    requireAssets
    returns (bool)
  {
    require(genderIndex >= 0 && genderIndex < 3, "MALFORMED_GENDER_INDEX");
    require(genderIndex == 2 || genderIndex == typeIndex, "MALFORMED_GENDER_TYPE");
    require(typeIndex >= 0 && typeIndex < 2, "MALFORMED_TYPE_INDEX");
    for (uint8 i = 0; i < Constants.N_CATEGORY; i++) {
      uint16 attrIndex = attributes[i];
      if (i == Constants.TYPE_INDEX) continue;
      assets.validate(typeIndex, attributes[i], i);
    }
    return true;
  }

  function renderPunkEnvironment (
    string memory output,
    UserPunk calldata punk
  )
    internal
    view
    returns (string memory)
  {
    output = string(abi.encodePacked(output, '<style id="pd">#punk{transform-origin: center center;}'));
    if (punk.direction == Constants.PD_ALTERNATE) {
      output = string(abi.encodePacked(output, '#punk { animation: flip 4s infinite linear; }'));
    } else {
      output = string(abi.encodePacked(output, '#punk { transform: scaleX(', punk.direction == Constants.PD_RIGHT ? '1' : '-1' ,'); }'));
    }
    output = string(abi.encodePacked(output, '</style>'));

    uint16 bgId = punk.attributeIndexes[Constants.BACKGROUND_INDEX];
    if (bgId != Constants.NONE) {
      output = string(abi.encodePacked(output,
        '<g class="c', Strings.toString(Constants.BACKGROUND_INDEX),'" id="a', Strings.toString(bgId), '">', 
        getSVGForPart(assets.getAsset(bgId, punk.fillIndexes[Constants.BACKGROUND_INDEX])),
        "</g>"
      ));
    }
    if (punk.genderIndex == Constants.TYPE_XYZ) {
      output = string(abi.encodePacked(output,
        '<g class="c1" id="nbf">', 
        getSVGForPart(assets.getAsset(Constants.ATTR_NB_FLAG, punk.fillIndexes[Constants.TYPE_INDEX])),
        "</g>"
      ));
    }
    return output;
  }

  function renderPunk (UserPunk calldata punk)
    public view
    requireAssets
    returns (MYPunk memory)
  {
    string memory svg;
    string memory jsonAttributes = getJsonProperty('Gender', assets.getGenderName(punk.genderIndex), true);
    jsonAttributes = string(abi.encodePacked(jsonAttributes, getJsonProperty('Direction', assets.getDirectionName(punk.direction), true)));

    uint16 attrIndex;
    MYPart memory part;

    svg = renderPunkEnvironment(svg, punk);

    svg = string(abi.encodePacked(svg, '<g id="punk">'));

    for (uint8 i = 0; i < Constants.N_CATEGORY; i++) {

      if (i == Constants.TYPE_INDEX) continue; // attributes that shouldn't be in metadata or render

      attrIndex = punk.attributeIndexes[i];
      part = assets.getAsset(attrIndex, punk.fillIndexes[i]);

      jsonAttributes = string(abi.encodePacked(jsonAttributes,
        getJsonProperty(
          assets.getCategoryNameByIndex(i), 
          part.asset.name, 
          i != Constants.N_CATEGORY - 1
        )
      ));

      if (i == Constants.BACKGROUND_INDEX) continue; // attributes that should be in metadata but not render

      svg = shouldRender(attrIndex)
        ? (string(abi.encodePacked(svg,
          '<g class="c', Strings.toString(i),'" id="a', Strings.toString(attrIndex), '">', 
          getSVGForPart(part),
          '</g>'
          )))
        : svg;

    }

    if (
      punk.attributeIndexes[Constants.NOSE_INDEX] == Constants.ATTR_CLOWN_NOSE_X || 
      punk.attributeIndexes[Constants.NOSE_INDEX] == Constants.ATTR_CLOWN_NOSE_Y
    ) {
      svg = string(abi.encodePacked(svg,
        '<g class="c', Strings.toString(Constants.NOSE_INDEX),'" id="a', Strings.toString(Constants.NOSE_INDEX), '">', 
        getSVGForPart(assets.getAsset(punk.attributeIndexes[Constants.NOSE_INDEX], punk.fillIndexes[Constants.NOSE_INDEX])),
        "</g>"
      ));
    }

    svg = string(abi.encodePacked(svg, '</g>'));

    return MYPunk({
      svg: svg,
      jsonAttributes: jsonAttributes
    });
  }
  
}

