//SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./Initializable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./SquareManagerContracts.sol";
import "./IERC20Upgradeable.sol";

contract SquareManager is Initializable, SquareManagerContracts {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;
	using SafeERC20Upgradeable for IERC20Upgradeable;
	using CountersUpgradeable for CountersUpgradeable.Counter;

    function initialize() external initializer {
        SquareManagerContracts.__SquareManagerContracts_init();
    }

    // User gets to claim Squares if they have not reached the max wallet limit
    function claimSquare(address _to,
                         uint256 _tokenId)
        external
        contractsAreSet
        contractNotFrozen
    {
        require(
            !walletMaxReached(),
            "SquareManager: Max per wallet reached"
        );

        require(
            isSquareAvailable(_tokenId),
            "SquareManager: Square already owned"
        );

        square.safeTransferFrom(address(this), msg.sender, _tokenId);

        emit SquareClaimed(msg.sender, _tokenId);
    }

    function balanceOf(address _owner)
        external
        override 
        view
        returns(uint256) 
    {
        return square.balanceOf(_owner);
    }

    function ownerOfSquare(uint256 _tokenId)
        external
        override
        view
        returns (address) 
    {
        
        return square.ownerOf(_tokenId);
    }

    //////////Helpers & owner

    function increaseMaxPerWallet(uint256 _maxTokens)
        external
        onlyAdminOrOwner
    {
        require(_maxTokens > maxTokensPerWallet,
            "Manager: Need to increase max tokens"
        );
        
        maxTokensPerWallet = _maxTokens;
    }

    function setTable()
        external
        onlyAdminOrOwner
        tableNotSet
    {

        setHomeTeam();
        setAwayTeam();
        //Will only be done once
        tableSet = true;
    }

    function setHomeTeam()
        private
    {
        homeNumbers = new uint256[](10);
        homeNumbers[0] = 0;
        homeNumbers[1] = 1;
        homeNumbers[2] = 2;
        homeNumbers[3] = 3;
        homeNumbers[4] = 4;
        homeNumbers[5] = 5;
        homeNumbers[6] = 6;
        homeNumbers[7] = 7;
        homeNumbers[8] = 8;
        homeNumbers[9] = 9;
        
        for (uint256 i = 0; i < homeNumbers.length; i++) {
            uint256 n = i + uint256(keccak256(abi.encodePacked(block.timestamp))) % (homeNumbers.length - i);
            uint256 temp = homeNumbers[n];
            homeNumbers[n] = homeNumbers[i];
            homeNumbers[i] = temp;
        }
    }

    function setAwayTeam()
        private
    {
        awayNumbers = new uint256[](10);
        awayNumbers[0] = 0;
        awayNumbers[1] = 1;
        awayNumbers[3] = 2;
        awayNumbers[2] = 3;
        awayNumbers[4] = 4;
        awayNumbers[5] = 5;
        awayNumbers[6] = 6;
        awayNumbers[7] = 7;
        awayNumbers[8] = 8;
        awayNumbers[9] = 9;

        for (uint256 i = 0; i < awayNumbers.length; i++) {
            uint256 n = i + (uint256(keccak256(abi.encodePacked(block.timestamp))) * 3) % (awayNumbers.length - i);
            uint256 temp = awayNumbers[n];
            awayNumbers[n] = awayNumbers[i];
            awayNumbers[i] = temp;
        }
    }

    function walletMaxReached()
        public
        view
        returns(bool)
    {
        return square.balanceOf(msg.sender) >= maxTokensPerWallet;
    }

    function isSquareAvailable(uint256 _tokenId)
        public 
        view
        returns(bool)
    {
        return square.ownerOf(_tokenId) == address(this);
    }

    function getAwayNumbers()
        public
        view
        returns(uint256[] memory)
    {
        return awayNumbers;
    }

    function getHomeNumbers()
        public
        view
        returns(uint256[] memory)
    {
        return homeNumbers;
    }
}
