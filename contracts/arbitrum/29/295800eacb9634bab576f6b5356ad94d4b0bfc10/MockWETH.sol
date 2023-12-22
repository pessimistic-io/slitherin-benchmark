// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import { ERC20Upgradeable } from "./ERC20Upgradeable.sol";
import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";

interface ITeamToken {
    function airdrop(address _beneficiary) external;
}

contract MockWETH is ERC20Upgradeable, OwnableUpgradeable {
    mapping(address => bool) public whitelist;
    mapping(address => bool) public claimed;
    address public campaignNft;
    address public almond;
    address public peanut;

    function initialize(
        address _campaignNft,
        address _almond,
        address _peanut
    ) external initializer {
        __ERC20_init("NFTPerp Mock WETH", "WETH");
        __Ownable_init();

        campaignNft = _campaignNft;
        almond = _almond;
        peanut = _peanut;
    }

    function faucet() external {
        address sender = msg.sender;
        require(!claimed[sender], "already claimed");
        claimed[sender] = true;
        _mint(sender, 5 ether);
        if ((totalSupply() % 2 ether) == 0) {
            ITeamToken(almond).airdrop(sender);
        } else {
            ITeamToken(peanut).airdrop(sender);
        }
    }

    function mintToInsuranceFund(address _insuranceFund) external onlyOwner {
        _mint(_insuranceFund, 10 ether);
    }

    /**
     * @dev whitelisted address is able to transfer tokens
     */
    function setWhitelist(address[] memory _users, bool[] memory _statuses) external onlyOwner {
        uint256 len = _users.length;
        require(len == _statuses.length, "length mismatch");
        for (uint256 i; i < len; ) {
            whitelist[_users[i]] = _statuses[i];
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev whether user is signed up participant
     */
    function _isParticipant(address _user) private view returns (bool) {
        (bool success, bytes memory data) = campaignNft.staticcall(
            abi.encodeWithSignature("balanceOf(address)", _user)
        );
        require(success && data.length != 0, "balance of failed");
        uint256 balance = abi.decode(data, (uint256));
        return balance != 0;
    }

    function _beforeTokenTransfer(
        address _from,
        address _to,
        uint256 _amount
    ) internal view override {
        if (_from != address(0)) {
            if (_isParticipant(_from)) {
                require(whitelist[_to], "non participant trading disabled");
            } else {
                require(
                    whitelist[_from] && (_isParticipant(_to) || whitelist[_to]),
                    "not participant trading disabled"
                );
            }
        }
    }
}

