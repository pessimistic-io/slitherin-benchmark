// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./ERC20Upgradeable.sol";
import "./OwnableUpgradeable.sol";

contract MockWETH is ERC20Upgradeable, OwnableUpgradeable {
    mapping(address => bool) public minted;
    mapping(address => bool) public protocolAddresses;

    function initialize() external initializer {
        __ERC20_init("NFTPerp Mock WETH", "WETH");
        __Ownable_init();
    }

    /**
     * trading competition faucet
     * @notice grants 5 mock weth, only once.
     */
    function nftperpFaucet() external {
        address sender = _msgSender();
        require(!minted[sender], "already minted");
        minted[sender] = true;
        _mint(_msgSender(), 5 ether);
    }

    /**
     * set protocol addresses
     */
    function setProtocolAddresses(address[] memory _addrs) external onlyOwner {
        for (uint256 i; i < _addrs.length; ) {
            protocolAddresses[_addrs[i]] = true;
            unchecked {
                ++i;
            }
        }
    }

    /**
     * transfers disabled
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(
            from == address(0) || protocolAddresses[from] || protocolAddresses[to],
            "non protocol transfers disabled"
        );
    }
}

