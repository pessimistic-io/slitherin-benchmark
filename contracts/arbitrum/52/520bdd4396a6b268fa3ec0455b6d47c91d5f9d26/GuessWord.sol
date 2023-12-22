// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "./ERC20.sol";

contract GuessWord {
    string[] private words;
    address token;
    address feeRecipient;
    address public owner;
    uint256 private currentWordId;
    uint256 private nonce;
    address[] private winners;
    mapping(uint => CurrentWord) givenWords;
    uint internal constant BP = 10_000;
    uint internal constant FEE_IN_BP = 1_000;

    event WordGuessed(address _player, string _word, uint _prizeAmount);

    struct Player {
        uint attemptsLeft;
        uint charsLeft;
        uint lastOpenCharTime;
        mapping(uint256 => uint256) charsOpenedNumbers;
        bool[] charsOpenedIndexes;
        bool flag;
    }

    struct CurrentWord {
        string word;
        mapping(address => Player) players;
    }

    event Withdrawal(uint amount, uint when);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor(address _token, address _feeRecipient) payable {
        token = _token;
        feeRecipient = _feeRecipient;
        owner = msg.sender;
        currentWordId = 0;
        nonce = 0;
    }

    function setWords(string[] memory _words) public onlyOwner() {
        words = _words;
        _setRandomWord();
    }

    function openChar(address _playerAddress) public {
        CurrentWord storage currentWord = givenWords[currentWordId];
        Player storage player = currentWord.players[_playerAddress];
        bytes memory word = bytes(currentWord.word);
        uint wordLength = _bytesStrlen(word);

        if (!player.flag) {
           player.charsLeft = wordLength;
           player.charsOpenedIndexes = new bool[](wordLength);
           player.attemptsLeft = 2;
           player.flag = true;
        }

        require(block.timestamp - player.lastOpenCharTime > 60, "You can open char every 10 minutes");

        require(player.charsLeft > 0, "All chars are open");

        IERC20 tokenContract = IERC20(token);

        require(tokenContract.transferFrom(_playerAddress, address(this), 1000000), 'Can not transfer tokens');

        uint256 charNumber = _random(player.charsLeft);
        uint charAt = _charAt(player, charNumber);

        player.charsOpenedNumbers[charNumber] = _charAt(player, player.charsLeft - 1);
        player.charsOpenedIndexes[charAt] = true;
        player.charsLeft -= 1;
        player.lastOpenCharTime = block.timestamp;
    }

    function guessWord(string memory _guess, address _playerAddress) public {
        CurrentWord storage currentWord = givenWords[currentWordId];
        Player storage player = currentWord.players[_playerAddress];

        require(player.attemptsLeft > 0, "Run out of tries");

        player.attemptsLeft -= 1;

        IERC20 tokenContract = IERC20(token);

        if (keccak256(abi.encodePacked(_guess)) == keccak256(abi.encodePacked(currentWord.word))) {
            uint amountToSend = _calculatePercent(tokenContract.balanceOf(address(this)), BP - FEE_IN_BP);
            uint feeAmount = _calculatePercent(tokenContract.balanceOf(address(this)), FEE_IN_BP);

            require(tokenContract.transfer(_playerAddress, amountToSend), 'Can not transfer tokens');
            require(tokenContract.transfer(feeRecipient, feeAmount), 'Can not transfer fee');

            winners.push(_playerAddress);
            _setRandomWord();
            emit WordGuessed(_playerAddress, _guess, amountToSend);
        }
    }

    function getToken() public view returns(address) {
        return token;
    }

    function getWinners() public view returns(address[] memory) {
        return winners;
    }

    function getCurrentWord(address _playerAddress) public view returns(string[] memory, bool, uint, uint, uint) {
        CurrentWord storage currentWord = givenWords[currentWordId];
        Player storage player = currentWord.players[_playerAddress];
        bytes memory word = bytes(currentWord.word);
        uint wordLength = _bytesStrlen(word);
        string[] memory wordChars = new string[](wordLength);

        if (!player.flag) {
            return (wordChars, player.flag, player.attemptsLeft, player.lastOpenCharTime, player.charsLeft);
        }

        for (uint i = 0; i < wordLength; i++) {
            if (player.charsOpenedIndexes[i]) {
                wordChars[i] = string(abi.encodePacked(word[i]));
            }
        }

        return (wordChars, player.flag, player.attemptsLeft, player.lastOpenCharTime, player.charsLeft);
    }

    function getPlayer(address _playerAddress) public view returns(bool, address, uint, uint, uint) {
        CurrentWord storage currentWord = givenWords[currentWordId];
        Player storage player = currentWord.players[_playerAddress];

        return (player.flag, address(_playerAddress), player.attemptsLeft, player.lastOpenCharTime, player.charsLeft);
    }


    function _setRandomWord() internal {
        uint256 index = _random(words.length);
        uint256 newWordId = _getNewCurrentWordId();

        CurrentWord storage newCurrentWord = givenWords[newWordId];
        newCurrentWord.word = words[index];
    }

    function _random(uint _max) internal view returns (uint256){
        return uint256(keccak256(abi.encodePacked(block.timestamp, msg.sender, block.number))) % _max;
    }

    function _getNewCurrentWordId() internal returns(uint256) {
        return ++currentWordId;
    }

    function _charAt(Player storage _player, uint256 _i) private returns(uint256) {
        if (_player.charsOpenedNumbers[_i] != 0) {
            return _player.charsOpenedNumbers[_i];
        } else {
            return _i;
        }
    }

    function _calculatePercent(uint256 amount, uint256 bps) internal pure returns (uint256) {
        require((amount * bps) >= BP);
        return amount * bps / BP;
    }

    function _bytesStrlen(bytes memory str) internal pure returns (uint length) {
        uint i = 0;
        bytes memory string_rep = str;

        while (i < string_rep.length)
        {
            if (string_rep[i] >> 7 == 0)
                i += 1;
            else if (string_rep[i] >> 5 == bytes1(uint8(0x6)))
                i += 2;
            else if (string_rep[i] >> 4 == bytes1(uint8(0xE)))
                i += 3;
            else if (string_rep[i] >> 3 == bytes1(uint8(0x1E)))
                i += 4;
            else
                i += 1;

            length++;
        }
        return length;
    }
}

