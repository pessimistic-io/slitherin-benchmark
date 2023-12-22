// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Ownable2Step} from "./Ownable2Step.sol";
import {ERC721Enumerable} from "./ERC721Enumerable.sol";
import {ERC721} from "./ERC721.sol";
import {Strings} from "./Strings.sol";

interface FloodBetaPassEvents {
    event Whitelisted(address indexed account);
    event Blacklisted(address indexed account);
}

error FloodBetaPass__NotWhitelisted();

contract FloodBetaPass is ERC721Enumerable, Ownable2Step, FloodBetaPassEvents {
    /// Mapping representing how many beta passes each account can mint. Zero means no mints left / not whitelisted.
    mapping(address => uint256) public mintsLeft;
    string public baseURI;
    uint256 public nextId = 1;

    constructor() ERC721("Flood Beta Pass", "FB") {}

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    /**
     *
     * View methods
     *
     */
    function whitelisted(address account) public view returns (bool) {
        return mintsLeft[account] > 0;
    }

    function nftsOf(address account) external view returns (uint256[] memory) {
        uint256 balance = balanceOf(account);
        uint256[] memory tokenIds = new uint256[](balance);
        for (uint256 i = 0; i < balance; i++) {
            tokenIds[i] = tokenOfOwnerByIndex(account, i);
        }
        return tokenIds;
    }

    /**
     *
     * Admin methods
     *
     */

    function whitelist(address account) external onlyOwner {
        mintsLeft[account]++;
        emit Whitelisted(account);
    }

    function whitelist(address account, uint256 amount) external onlyOwner {
        mintsLeft[account] += amount;
        emit Whitelisted(account);
    }

    function whitelist(address[] calldata accounts) external onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            mintsLeft[accounts[i]]++;
            emit Whitelisted(accounts[i]);
        }
    }

    function whitelist(address[] calldata accounts, uint256[] calldata amounts) external onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            mintsLeft[accounts[i]] += amounts[i];
            emit Whitelisted(accounts[i]);
        }
    }

    function blacklist(address account) external onlyOwner {
        delete mintsLeft[account];
        emit Blacklisted(account);
    }

    function blacklist(address[] calldata accounts) external onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            delete mintsLeft[accounts[i]];
            emit Blacklisted(accounts[i]);
        }
    }

    function mint() external {
        if (mintsLeft[msg.sender] == 0) {
            revert FloodBetaPass__NotWhitelisted();
        }
        mintsLeft[msg.sender]--;
        _mint(msg.sender, nextId++);
    }

    function mint(address account) external {
        if (mintsLeft[account] == 0) {
            revert FloodBetaPass__NotWhitelisted();
        }
        mintsLeft[account]--;
        _mint(account, nextId++);
    }

    function setBaseURI(string memory _baseURI) external onlyOwner {
        baseURI = _baseURI;
    }
}

