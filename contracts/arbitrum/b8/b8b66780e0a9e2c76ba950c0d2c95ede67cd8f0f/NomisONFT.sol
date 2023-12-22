// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "./ONFT721Upgradeable.sol";

///////////////////////////////////////////////////////////////
//  ___   __    ______   ___ __ __    ________  ______       //
// /__/\ /__/\ /_____/\ /__//_//_/\  /_______/\/_____/\      //
// \::\_\\  \ \\:::_ \ \\::\| \| \ \ \__.::._\/\::::_\/_     //
//  \:. `-\  \ \\:\ \ \ \\:.      \ \   \::\ \  \:\/___/\    //
//   \:. _    \ \\:\ \ \ \\:.\-/\  \ \  _\::\ \__\_::._\:\   //
//    \. \`-\  \ \\:\_\ \ \\. \  \  \ \/__\::\__/\ /____\:\  //
//     \__\/ \__\/ \_____\/ \__\/ \__\/\________\/ \_____\/  //
//                                                           //
///////////////////////////////////////////////////////////////

/**
 * @title NomisONFT.
 * @author Nomis team.
 * @notice Interface for Nomis ONFT contract.
 */
contract NomisONFT is ONFT721Upgradeable {
    /*#########################
    ##       Variables       ##
    ##########################*/

    /**
     * @dev The base URI.
     */
    string public baseURI;

    /**
     * @dev The Nomis Score contract address.
     */
    address public nomisScore;

    /*#########################
    ##        Mappings       ##
    ##########################*/

    /**
     * @dev Mapping from token ID to token URI.
     */
    mapping(uint256 => string) internal _tokenURI;

    /**
     * @dev Mapping from token ID to minter address.
     */
    mapping(uint256 => address) public minterOf;

    /*#########################
    ##         Events        ##
    ##########################*/

    /**
     * @dev Emitted when an ONFT is minted.
     * @param tokenId The token ID of the minted ONFT.
     * @param tokenURI The token URI of the minted ONFT.
     * @param minter The address of the account that minted the ONFT.
     */
    event ONFTMinted(
        uint256 indexed tokenId,
        string indexed tokenURI,
        address indexed minter
    );

    /*#########################
    ##        Modifiers      ##
    ##########################*/

    modifier onlyNomis() {
        require(msg.sender == nomisScore, "Forbidden");
        _;
    }

    /*#########################
    ##      Constructor      ##
    ##########################*/

    /**
     * @notice Construct a new NomisONFT contract.
     * @dev The Nomis Score contract address is immutable.
     * @dev The base URI is set to the empty string.
     * @param _nomisScore The NomisScore contract address.
     * @param _minGasToTransfer The minimum gas price to transfer ONFTs.
     * @param _lzEndpoint The LayerZero endpoint.
     */
    function initialize(
        address _nomisScore,
        uint256 _minGasToTransfer,
        address _lzEndpoint
    ) public initializer {
        __ONFT721Upgradeable_init(
            "NomisONFT",
            "NMSSO",
            _minGasToTransfer,
            _lzEndpoint
        );

        nomisScore = _nomisScore;
    }

    /*#########################
    ##    Write Functions    ##
    ##########################*/

    /**
     * @notice Mint a new ONFT.
     * @dev Only the ONFT contract can call this function.
     * @param to The address of the new ONFT owner.
     * @param tokenId The minted token id.
     * @param tokenURI_ The token URI of the minted token.
     */
    function mint(
        address to,
        uint256 tokenId,
        string memory tokenURI_
    ) external onlyNomis {
        _mint(to, tokenId);
        minterOf[tokenId] = to;
        _tokenURI[tokenId] = tokenURI_;

        emit ONFTMinted(tokenId, tokenURI_, to);
    }

    /*#########################
    ##    Read Functions    ##
    ##########################*/

    /**
     * @notice Get the token URI.
     * @param tokenId The token id.
     * @return The token URI.
     */
    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        _requireMinted(tokenId);

        return _tokenURI[tokenId];
    }
}

