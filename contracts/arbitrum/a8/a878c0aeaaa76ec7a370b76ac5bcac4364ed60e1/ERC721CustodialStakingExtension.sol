// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.15;

import "./Initializable.sol";
import "./Ownable.sol";
import "./ERC165Storage.sol";

import "./Address.sol";
import "./Counters.sol";
import "./ReentrancyGuard.sol";
import "./IERC20.sol";
import "./IERC721.sol";

import {IERC721LockableExtension} from "./ERC721LockableExtension.sol";

import "./ERC721StakingExtension.sol";

/**
 * @author Flair (https://flair.finance)
 */
interface IERC721CustodialStakingExtension {
    function hasERC721CustodialStakingExtension() external view returns (bool);

    function tokensInCustody(
        address staker,
        uint256 startTokenId,
        uint256 endTokenId
    ) external view returns (bool[] memory);
}

/**
 * @author Flair (https://flair.finance)
 */
abstract contract ERC721CustodialStakingExtension is
    IERC721CustodialStakingExtension,
    ERC721StakingExtension
{
    mapping(uint256 => address) public stakers;

    /* INIT */

    function __ERC721CustodialStakingExtension_init(
        uint64 _minStakingDuration,
        uint64 _maxStakingTotalDurations
    ) internal onlyInitializing {
        __ERC721CustodialStakingExtension_init_unchained();
        __ERC721StakingExtension_init_unchained(
            _minStakingDuration,
            _maxStakingTotalDurations
        );
    }

    function __ERC721CustodialStakingExtension_init_unchained()
        internal
        onlyInitializing
    {
        _registerInterface(type(IERC721CustodialStakingExtension).interfaceId);
    }

    /* PUBLIC */

    function hasERC721CustodialStakingExtension() external pure returns (bool) {
        return true;
    }

    function tokensInCustody(
        address staker,
        uint256 startTokenId,
        uint256 endTokenId
    ) external view returns (bool[] memory tokens) {
        tokens = new bool[](endTokenId - startTokenId + 1);

        for (uint256 i = startTokenId; i <= endTokenId; i++) {
            if (stakers[i] == staker) {
                tokens[i - startTokenId] = true;
            }
        }

        return tokens;
    }

    /* INTERNAL */

    function _stake(
        address operator,
        uint64 currentTime,
        uint256 tokenId
    ) internal virtual override {
        stakers[tokenId] = operator;
        super._stake(operator, currentTime, tokenId);
        IERC721(ticketToken).transferFrom(operator, address(this), tokenId);
    }

    function _unstake(
        address operator,
        uint64 currentTime,
        uint256 tokenId
    ) internal virtual override {
        require(stakers[tokenId] == operator, "NOT_STAKER");
        delete stakers[tokenId];

        super._unstake(operator, currentTime, tokenId);
        IERC721(ticketToken).transferFrom(address(this), operator, tokenId);
    }

    function _beforeClaim(
        uint256 ticketTokenId_,
        address claimToken_,
        address beneficiary_
    ) internal virtual override {
        claimToken_;

        if (stakers[ticketTokenId_] == address(0)) {
            require(
                IERC721(ticketToken).ownerOf(ticketTokenId_) == beneficiary_,
                "NOT_NFT_OWNER"
            );
        } else {
            require(beneficiary_ == stakers[ticketTokenId_], "NOT_STAKER");
        }
    }
}

