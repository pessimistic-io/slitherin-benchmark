// SPDX-License-Identifier: CC0-1.0
// EPS Contracts v2.0.0
// www.eternalproxy.com

/**
 
@dev EPS4907. Implement ERC4907 using EPS.

*/

import "./IEPSDelegationRegister.sol";
import "./IERC721.sol";

pragma solidity 0.8.19;

interface IEPS4907 {
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
  function userOf(uint256 tokenId_) external view returns (address userOf_);

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
    external
    view
    returns (
      address primaryBeneficiary_,
      address[] memory secondaryBeneficiaries_
    );

  /**
   * @dev Returns the EPS beneficiary balance of the `beneficiary` address.
   *
   * Requirements:
   *
   * - `tokenId` must exist.
   */
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
  ) external view returns (uint256 beneficaryBalance);
}

