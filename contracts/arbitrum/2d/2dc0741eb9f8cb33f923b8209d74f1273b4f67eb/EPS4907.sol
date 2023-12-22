// SPDX-License-Identifier: CC0-1.0
// EPS Contracts v2.0.0
// www.eternalproxy.com

/**
 
@dev EPS4907. Implement ERC4907 using EPS.

*/

import "./IEPS4907.sol";

pragma solidity 0.8.19;

abstract contract EPS4907 is IEPS4907 {
  uint256 private constant ERC4907_USAGE_TYPE = 16;

  // EPS Register
  IEPSDelegationRegister internal immutable epsRegister;

  /** ====================================================================================================================
   *                                                     CONSTRUCTOR
   * =====================================================================================================================
   */
  /** ____________________________________________________________________________________________________________________
   *                                                                                                        -->CONSTRUCTOR
   * @dev constructor           Initalise the EPS register address
   * ---------------------------------------------------------------------------------------------------------------------
   * @param epsRegister_        The EPS register address (0x888888888888660F286A7C06cfa3407d09af44B2 on most chains)
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  constructor(address epsRegister_) {
    epsRegister = IEPSDelegationRegister(epsRegister_);
  }

  /** ====================================================================================================================
   *                                                   IMPLEMENTATION
   * =====================================================================================================================
   */
  /** ____________________________________________________________________________________________________________________
   *                                                                                                      -->IMPLEMENATION
   * @dev userOf                Return an ERC4907 compliant user for this tokenId
   * ---------------------------------------------------------------------------------------------------------------------
   * @param tokenId_            The tokenId being queried
   * ---------------------------------------------------------------------------------------------------------------------
   * @return userOf_            The user for this tokenID, as per the EPS register
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function userOf(
    uint256 tokenId_
  ) public view virtual returns (address userOf_) {
    (address primaryBeneficiary, ) = beneficiaryOf(
      tokenId_,
      ERC4907_USAGE_TYPE,
      false,
      true
    );
    // If there is no delegation in place then the beneficiary that is returned
    // will be the owner. For consistency with the returned result for ERC4907
    // we want to return the zero address under these circumstances (i.e. there
    // is no "_user" for this tokenId at this time)
    if (primaryBeneficiary == IERC721(address(this)).ownerOf(tokenId_)) {
      return (address(0));
    } else {
      return primaryBeneficiary;
    }
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                      -->IMPLEMENATION
   * @dev beneficiaryOf              Returns the EPS beneficiary (or beneficiaries) of the `tokenId` token.
   * ---------------------------------------------------------------------------------------------------------------------
   * @param tokenId_                 The tokenId being queried
   * ---------------------------------------------------------------------------------------------------------------------
   * @param usageType_               The usage ID being queried (e.g. 0 for all, 6 for social media).
   * ---------------------------------------------------------------------------------------------------------------------
   * @param includeSecondary_        Include secondary (i.e. non-unique) results?
   * ---------------------------------------------------------------------------------------------------------------------
   * @param includeRental_           Include rental (these ARE unique) results?
   * ---------------------------------------------------------------------------------------------------------------------
   * @return primaryBeneficiary_     The primary (and unique) beneficiary for this token ID
   * ---------------------------------------------------------------------------------------------------------------------
   * @return secondaryBeneficiaries_  An array of secondary beneficiaries (if any)
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function beneficiaryOf(
    uint256 tokenId_,
    uint256 usageType_,
    bool includeSecondary_,
    bool includeRental_
  )
    public
    view
    returns (
      address primaryBeneficiary_,
      address[] memory secondaryBeneficiaries_
    )
  {
    return (
      epsRegister.beneficiaryOf(
        address(this),
        tokenId_,
        usageType_,
        includeSecondary_,
        includeRental_
      )
    );
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                      -->IMPLEMENATION
   * @dev beneficiaryBalanceOf       Returns the EPS beneficiary balance of the `beneficiary` address.
   * ---------------------------------------------------------------------------------------------------------------------
   * @param beneficiary_             The address being queried
   * ---------------------------------------------------------------------------------------------------------------------
   * @param usageType_               The usage ID being queried (e.g. 0 for all, 6 for social media).
   * ---------------------------------------------------------------------------------------------------------------------
   * @param includeSecondary_        Include secondary (i.e. non-unique) results?
   * ---------------------------------------------------------------------------------------------------------------------
   * @param includeRental_           Include rental (these ARE unique) results?
   * ---------------------------------------------------------------------------------------------------------------------
   * @return beneficaryBalance       The balance for this beneficiary address
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */

  function beneficiaryBalanceOf(
    address beneficiary_,
    uint256 usageType_,
    bool includeSecondary_,
    bool includeRental_
  ) public view returns (uint256 beneficaryBalance) {
    return
      epsRegister.beneficiaryBalanceOf(
        beneficiary_,
        address(this),
        usageType_,
        false,
        0,
        includeSecondary_,
        includeRental_
      );
  }

  /** ____________________________________________________________________________________________________________________
   *                                                                                                      -->IMPLEMENATION
   * @dev supportsInterface
   * @dev Returns true if this contract implements the interface defined by
   * `interfaceId`. See the corresponding
   * [EIP section](https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified)
   * to learn more about how these ids are created.
   *
   * This function call must use less than 30000 gas.
   * ---------------------------------------------------------------------------------------------------------------------
   * @param interfaceId              The interface ID being queried
   * ---------------------------------------------------------------------------------------------------------------------
   * @return bool                    True if supported
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function supportsInterface(
    bytes4 interfaceId
  ) public view virtual returns (bool) {
    // The interface IDs are constants representing the first 4 bytes
    // of the XOR of all function selectors in the interface.
    // See: [ERC165](https://eips.ethereum.org/EIPS/eip-165)
    // (e.g. `bytes4(i.functionA.selector ^ i.functionB.selector ^ ...)`)
    return
      interfaceId == 0xad092b5c || // ERC165 interface ID for IERC4907.
      interfaceId == 0xd50ef07c; // ERC165 interface ID for IEPS4907
  }
}

