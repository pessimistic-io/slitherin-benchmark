// SPDX-License-Identifier: MIT

/**
    IMPORTANT NOTICE:
    This smart contract was written and deployed by the software engineers at 
    https://highstack.co in a contractor capacity.
    
    Highstack is not responsible for any malicious use or losses arising from using 
    or interacting with this smart contract.

    THIS CONTRACT IS PROVIDED ON AN “AS IS” BASIS. USE THIS SOFTWARE AT YOUR OWN RISK.
    THERE IS NO WARRANTY, EXPRESSED OR IMPLIED, THAT DESCRIBED FUNCTIONALITY WILL 
    FUNCTION AS EXPECTED OR INTENDED. PRODUCT MAY CEASE TO EXIST. NOT AN INVESTMENT, 
    SECURITY OR A SWAP. TOKENS HAVE NO RIGHTS, USES, PURPOSE, ATTRIBUTES, 
    FUNCTIONALITIES OR FEATURES, EXPRESS OR IMPLIED, INCLUDING, WITHOUT LIMITATION, ANY
    USES, PURPOSE OR ATTRIBUTES. TOKENS MAY HAVE NO VALUE. PRODUCT MAY CONTAIN BUGS AND
    SERIOUS BREACHES IN THE SECURITY THAT MAY RESULT IN LOSS OF YOUR ASSETS OR THEIR 
    IMPLIED VALUE. ALL THE CRYPTOCURRENCY TRANSFERRED TO THIS SMART CONTRACT MAY BE LOST.
    THE CONTRACT DEVLOPERS ARE NOT RESPONSIBLE FOR ANY MONETARY LOSS, PROFIT LOSS OR ANY
    OTHER LOSSES DUE TO USE OF DESCRIBED PRODUCT. CHANGES COULD BE MADE BEFORE AND AFTER
    THE RELEASE OF THE PRODUCT. NO PRIOR NOTICE MAY BE GIVEN. ALL TRANSACTION ON THE 
    BLOCKCHAIN ARE FINAL, NO REFUND, COMPENSATION OR REIMBURSEMENT POSSIBLE. YOU MAY 
    LOOSE ALL THE CRYPTOCURRENCY USED TO INTERACT WITH THIS CONTRACT. IT IS YOUR 
    RESPONSIBILITY TO REVIEW THE PROJECT, TEAM, TERMS & CONDITIONS BEFORE USING THE 
    PRODUCT.

**/

pragma solidity ^0.8.4;

import "./ERC721Enumerable.sol";
import "./Counters.sol";
import "./ReentrancyGuard.sol";
import "./Ownable.sol";
import "./Strings.sol";
import "./console.sol";

contract GalaxyVillainsChineseNewYear is
    ERC721Enumerable,
    Ownable,
    ReentrancyGuard
{
    // Initialize Packages
    using Counters for Counters.Counter;
    using Strings for *;
    Counters.Counter private _tokenIdTracker;

    // Constants
    string private EMPTY_STRING = "";

    // Settings
    uint256 public MAX_ELEMENTS = 100;

    // Data Structures
    struct BaseTokenUriById {
        uint256 startId;
        uint256 endId;
        string baseURI;
    }
    BaseTokenUriById[] public baseTokenUris;


    constructor(
        string memory name,
        string memory ticker,
        address _vaultAddress
    ) ERC721(name, ticker) {
        _mintAmount(100, _vaultAddress);
    }

    /***********************/
    /***********************/
    /***********************/
    /*** ADMIN FUNCTIONS ***/
    /***********************/
    /***********************/
    /***********************/
    /***********************/

    function setMaxElements(uint256 maxElements) public onlyOwner {
        require(maxElements >= totalSupply(), "Cannot decrease under existing supply");
        MAX_ELEMENTS = maxElements;
    }


    function clearBaseUris() public onlyOwner {
        delete baseTokenUris;
    }

    function setBaseURI(
        string memory baseURI,
        uint256 startId,
        uint256 endId
    ) public onlyOwner {
        require(
            keccak256(bytes(tokenURI(startId))) ==
                keccak256(bytes(EMPTY_STRING)),
            "Start ID Overlap"
        );
        require(
            keccak256(bytes(tokenURI(endId))) == keccak256(bytes(EMPTY_STRING)),
            "End ID Overlap"
        );
        baseTokenUris.push(
            BaseTokenUriById({startId: startId, endId: endId, baseURI: baseURI})
        );
    }

    /************************/
    /************************/
    /************************/
    /*** PUBLIC FUNCTIONS ***/
    /************************/
    /************************/
    /************************/
    /************************/

    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        uint256 length = baseTokenUris.length;
        for (uint256 interval = 0; interval < length; ++interval) {
            BaseTokenUriById storage baseTokenUri = baseTokenUris[interval];
            if (
                baseTokenUri.startId <= tokenId && baseTokenUri.endId >= tokenId
            ) {
                return
                    string(
                        abi.encodePacked(
                            baseTokenUri.baseURI,
                            tokenId.toString(),
                            ".json"
                        )
                    );
            }
        }
        return "";
    }

    function totalSupply() public view returns (uint256) {
        return _tokenIdTracker.current();
    }


    function _mintAmount(uint256 amount, address wallet) private {
        for (uint8 i = 0; i < amount; i++) {
            while (
                !(rawOwnerOf(_tokenIdTracker.current() + 1) == address(0))
            ) {
                _tokenIdTracker.increment();
            }
            _mintAnElement(wallet);
        }
    }

    function _mintAnElement(address _to) private {
        _tokenIdTracker.increment();
        _safeMint(_to, _tokenIdTracker.current());
    }

    function walletOfOwner(address _owner)
        external
        view
        returns (uint256[] memory)
    {
        uint256 tokenCount = balanceOf(_owner);

        uint256[] memory tokensId = new uint256[](tokenCount);
        for (uint256 i = 0; i < tokenCount; i++) {
            tokensId[i] = tokenOfOwnerByIndex(_owner, i);
        }

        return tokensId;
    }
}

