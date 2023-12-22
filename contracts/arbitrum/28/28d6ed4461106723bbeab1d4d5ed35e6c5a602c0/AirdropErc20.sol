// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./IERC20Upgradeable.sol";

contract ReadonAirdrop is OwnableUpgradeable,UUPSUpgradeable {
    event Received(address, uint);

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    function dropTokens(
        address _tokenAddr,
        address[] memory _recipients,
        uint256[] memory _amounts
    ) public onlyOwner returns (bool) {
        require(_recipients.length == _amounts.length, "ERC:length mismatch");
        for (uint16 i = 0; i < _recipients.length; i++) {
            require(IERC20Upgradeable(_tokenAddr).transfer(_recipients[i], _amounts[i]));
        }

        return true;
    }

    function dropMain(
        address payable[] memory _recipients,
        uint256[] memory _amounts
    ) public onlyOwner returns (bool) {
        require(_recipients.length == _amounts.length, "ERC:length mismatch");
        for (uint16 i = 0; i < _recipients.length; i++) {
            _recipients[i].transfer(_amounts[i]);
        }

        return true;
    }

    function dropMix(
        address _tokenAddr,
        address payable[] memory _recipients,
        uint256[] memory token_amounts,
        uint256[] memory gas_amounts
    ) public onlyOwner returns (bool) {
        require(
            _recipients.length == gas_amounts.length &&
                gas_amounts.length == token_amounts.length,
            "ERC:length mismatch"
        );
        for (uint16 i = 0; i < gas_amounts.length; i++) {
            require(
                IERC20Upgradeable(_tokenAddr).transfer(_recipients[i], token_amounts[i])
            );
            _recipients[i].transfer(gas_amounts[i]);
        }

        return true;
    }

    function withdrawTokens(address _tokenAddr,address beneficiary) public onlyOwner {
        require(
            IERC20Upgradeable(_tokenAddr).transfer(
                beneficiary,
                IERC20Upgradeable(_tokenAddr).balanceOf(address(this))
            )
        );
    }

    function withdrawEther(address payable beneficiary) public onlyOwner {
        beneficiary.transfer(address(this).balance);
    }
    function initialize() public initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyOwner
    {}
}

