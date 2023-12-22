// SPDX-License-Identifier: CC0
pragma solidity >=0.8.13;

import "./IHats.sol";

/// @notice Single owner authorization mixin using Hats Protocol
/// @dev Common logic across initializable and standard versions
/// @author Hats Protocol
abstract contract HatsOwnedCommon {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event OwnerHatUpdated(
        uint256 indexed ownerHat,
        address indexed hatsAddress
    );

    /*//////////////////////////////////////////////////////////////
                            OWNERSHIP STORAGE
    //////////////////////////////////////////////////////////////*/

    IHats internal HATS;
    uint256 public ownerHat;

    modifier onlyOwner() virtual {
        require(HATS.isWearerOfHat(msg.sender, ownerHat), "UNAUTHORIZED");

        _;
    }

    /*//////////////////////////////////////////////////////////////
                             OWNERSHIP LOGIC
    //////////////////////////////////////////////////////////////*/

    function setOwnerHat(uint256 _ownerHat, address _hatsContract)
        public
        virtual
        onlyOwner
    {
        uint256 changes;

        if (ownerHat != _ownerHat) {
            ownerHat = _ownerHat;
            // max of 2, so will never overflow
            unchecked {
                ++changes;
            }
        }

        IHats hats = IHats(_hatsContract);

        if (HATS != hats) {
            HATS = hats;
            // max of 2, so will never overflow
            unchecked {
                ++changes;
            }
        }

        require(changes > 0, "NO CHANGES");

        emit OwnerHatUpdated(_ownerHat, _hatsContract);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONs
    //////////////////////////////////////////////////////////////*/

    function getHatsContract() public view returns (address) {
        return address(HATS);
    }
}

