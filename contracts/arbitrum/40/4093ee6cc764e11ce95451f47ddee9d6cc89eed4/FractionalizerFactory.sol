// SPDX-License-Identifier: Unlicensed

pragma solidity =0.8.10;

import { Fractionalizer721 } from "./Fractionalizer721.sol";
import { Fractionalizer1155 } from "./Fractionalizer1155.sol";

/** 
  @notice 
  Allows to deploy fractionalizers per NFT collection in a cheaper way.
*/
contract FractionalizerFactory {

    //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//
    error FRACTIONALIZER_EXISTS();
    
    /**
      @notice
      NFT collection -> fractionalizer mapping to prevent duplicate deployments
    */
    mapping(address => address) public getFractionalizer;

    /**
      @notice
      Deploys Fractionalizer with create2(https://eips.ethereum.org/EIPS/eip-1014)

      @param oceanAddress Ocean contract address.
      @param nftCollection_ NFT collection address
      @param exchangeRate_ No of fungible tokens per each NFT.

      @return fractionalizer fractionalizer contract address
    */
    function deploy(
        address oceanAddress,
        address nftCollection_,
        uint256 exchangeRate_,
        bool isErc721
    ) external returns(address fractionalizer) {
      if (getFractionalizer[nftCollection_] != address(0)) revert FRACTIONALIZER_EXISTS();

      // constructing the deployment bytecode
      bytes memory _creationCode = isErc721 ? type(Fractionalizer721).creationCode : type(Fractionalizer1155).creationCode;
      bytes memory _deploymentArgEncoding = abi.encode(oceanAddress,nftCollection_,exchangeRate_);
      bytes memory _bytecode = abi.encodePacked(_creationCode, _deploymentArgEncoding);

      // constructing salt
      uint256 _salt = uint256(keccak256(_deploymentArgEncoding));
      assembly {
        fractionalizer := create2(0, add(_bytecode, 0x20), mload(_bytecode), _salt)

        if iszero(extcodesize(fractionalizer)) {
            revert(0, 0)
        }
      }
      getFractionalizer[nftCollection_] = fractionalizer;
    }
}
