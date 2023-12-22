pragma solidity >0.8.0;

import "./IERC721Metadata.sol";
import "./IERC721.sol";

interface IArkenOptionNFT is IERC721, IERC721Metadata {
    error NotExist();
    error NotAuthorized();
    error ExerciseAmountIsNotReduced(uint256 currentAmount, uint256 newAmount);

    event MintTokenData(uint256 tokenId, TokenData data);
    event UpdateBaseURI(string baseURI);

    struct TokenData {
        uint256 unlockedAt;
        uint256 expiredAt;
        uint256 unlockPrice;
        /**
         * @dev: price = quote/base
         * e.g. ARKEN-USDC = 10 USDC / 1 ARKEN
         * means to exercise all of this NFT, one have to give exerciseAmount * 10 in USDC
         */
        uint256 exercisePrice;
        uint256 exerciseAmount;
        uint256 optionType;
    }

    function mint(
        address to,
        TokenData calldata data
    ) external returns (uint256 tokenId);

    function updateBaseURI(string calldata baseURI) external;

    function tokenData(
        uint256 tokenId
    ) external view returns (TokenData memory, uint256 createdAt);

    function createdAt(uint256 tokenId) external view returns (uint256);
}

