// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface IBingoCard {
    event Revealed(
        uint256 indexed cardId,
        address indexed revealer,
        address indexed signer,
        uint8[][] numbers
    );

    /** @notice Number of rows of the card */
    function rows() external view returns (uint8);

    /** @notice Number of columns of the card */
    function columns() external view returns (uint8);

    /**
     * @notice Number picking-restrictions of each space
     * @dev row -> col -> [min,max] (0: no restrictions)
     */
    function restrictions() external view returns (uint8[2][][] memory);

    /** @dev Line: [rowIndex, colIndex][] (uint8[2][]) */
    function lines() external view returns (uint8[2][][] memory);

    /** @dev [rowIndex, colIndex][] */
    function freeSpaces() external view returns (uint8[2][] memory);

    function getCardGame(
        uint256 cardId
    ) external view returns (
        address gameContract,
        uint256 gameId
    );

    function getCardNumbers(
        uint256 cardId
    ) external view returns(uint8[][] memory cardNumbers);

    function matchedLines(
        uint256 cardId
    ) external view returns (uint8 lineCount);

    function calculateMatchedLineCounts(
        uint8[][] memory cardNumbers,
        uint256 encodedSelectNumbers
    ) external view returns  (uint8 lineCount);

    function estimateMatchedLines(
        uint8[][] memory cardNumbers,
        uint8[] memory selectedNumbers
    ) external view returns (uint8 lineCounts);

    function reveal(
        uint256 cardId,
        bytes calldata gameLabel,
        bytes calldata signedGameLabel,
        uint8[][] calldata cardNumbers
    ) external;

    /*
    ██    ██ ████████ ██ ██      ███████
    ██    ██    ██    ██ ██      ██      - encode/decode card numbers
    ██    ██    ██    ██ ██      ███████ - encode/decode marked spaces
    ██    ██    ██    ██ ██           ██ - verify signer tester
     ██████     ██    ██ ███████ ███████ - encode selected numbers helper
    */

    function encodeCardNumbers(
        uint8[][] calldata cardNumbers
    ) external view returns (bytes memory encodedCardNumbers);

    function decodeCardNumbers(
        bytes memory encodedCardNumbers
    ) external view returns (uint8[][] memory cardNumbers);

    /** @dev [rowIndex, colIndex][] */
    function encodeMarkedSpaces(
        uint8[2][] calldata markedSpaces
    ) external view returns (uint256 encodedMarkedSpaces);

    function decodeMarkedSpaces(
        uint256 encodedMarkedSpaces
    ) external view returns (uint8[2][] memory markedSpaces);

    function verifySigner(
        uint256 cardId,
        bytes memory salt,
        uint8[][] memory cardNumbers,
        address signer
    ) external view returns (bool);

    function encodeSelectedNumbers(
        uint8[] calldata selectedNumbers
    ) external pure returns (uint256 encodedSelectedNumbers);

    function decodeSelectedNumbers(
        uint256 encodedSelectedNumbers
    ) external pure returns (uint8[] memory selectedNumbers);

    /*
     █████  ██████  ███    ███ ██ ███    ██
    ██   ██ ██   ██ ████  ████ ██ ████   ██
    ███████ ██   ██ ██ ████ ██ ██ ██ ██  ██ - bind card to game
    ██   ██ ██   ██ ██  ██  ██ ██ ██  ██ ██ - set valid lines
    ██   ██ ██████  ██      ██ ██ ██   ████ - set free spaces
    */

    function mint(
        address to,
        uint256 gameId,
        bytes calldata encryptedContent
    ) external returns (uint256 cardId);

    function editUnplayedCard(
        uint256 cardId,
        bytes calldata encryptedContent
    ) external;

    function bindCardGame(
        uint256 cardId,
        address gameContract,
        uint256 gameId
    ) external;

    /*
     ██████  ██     ██ ███    ██ ███████ ██████
    ██    ██ ██     ██ ████   ██ ██      ██   ██
    ██    ██ ██  █  ██ ██ ██  ██ █████   ██████
    ██    ██ ██ ███ ██ ██  ██ ██ ██      ██   ██
     ██████   ███ ███  ██   ████ ███████ ██   ██
    */

    function setRestrictions(uint8[2][][] calldata spaceNumberRestrictions) external;
    function setLines(uint8[2][][] calldata validLines) external;
    function setFreeSpaces(uint8[2][] calldata freeSpacePositions) external;
    function setBindingGame(address gameAddress) external;
    function addMinter(address minter) external;
    function removeMinter(address minter) external;
}

