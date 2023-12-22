// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8;

import "./AdvancedONFT721A.sol";


error exceedMaxTokensPerMint();

contract PrimeGenesis is AdvancedONFT721A {

  uint maxTokensPerMint = 5;

  constructor(
    string memory _name,
    string memory _symbol,
    address _lzEndpoint,
    uint256 _startId,
    uint256 _maxId,
    uint256 _maxGlobalId,
    string memory _baseTokenURI,
    string memory _hiddenURI,
    uint16 _tax,
    uint128 _price,
    uint128 _wlPrice,
    address token,
    address _taxRecipient,
    bool preMint,
    address _beneficiary
  ) AdvancedONFT721A( _name, _symbol, _lzEndpoint, _startId, _maxId, _maxGlobalId, _baseTokenURI, _hiddenURI, _tax, _price, _wlPrice, token,  _taxRecipient, _beneficiary) {
    if (preMint) {
      // increments of 4 to make transfer gas cheaper
      for(uint i; i < 10;) {
        _mint(_beneficiary, 5);
        unchecked {
          i++;
        }
      }
    }
  }


  function whitelistMint(uint _nbTokens, bytes32[] calldata _merkleProof) public payable override {
    if(_nbTokens > maxTokensPerMint) _revert(exceedMaxTokensPerMint.selector);
    super.whitelistMint(_nbTokens, _merkleProof);
  }

  function mint(uint _nbTokens) public payable override {
    if(_nbTokens > maxTokensPerMint) _revert(exceedMaxTokensPerMint.selector);
    super.mint(_nbTokens);
  }

  function setMaxTokensPerMint(uint64 _maxTokensPerMint ) external onlyBenficiaryAndOwner {
    maxTokensPerMint = _maxTokensPerMint;
  }




}
