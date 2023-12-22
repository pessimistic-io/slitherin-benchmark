//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./CorruptionState.sol";

contract Corruption is Initializable, CorruptionState {

    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    function initialize() external initializer {
        CorruptionState.__CorruptionState_init();
    }

    function setCorruptionStreamInfo(address _account, uint128 _newRatePerSecond, uint256 _generatedCorruptionCap) external onlyAdminOrOwner {
        // Mint any tokens at the old rate.
        //
        _mintAccumulatedTokens(_account);

        addressToStreamInfo[_account].timeLastMinted = uint128(block.timestamp);
        addressToStreamInfo[_account].ratePerSecond = _newRatePerSecond;
        addressToStreamInfo[_account].generatedCorruptionCap = _generatedCorruptionCap;

        emit CorruptionStreamModified(_account, _newRatePerSecond, _generatedCorruptionCap);
    }

    function setCorruptionStreamBoost(address _account, uint32 _boost) external onlyAdminOrOwner {
        if(addressToStreamInfo[_account].boost == _boost) {
            return;
        }
        // Mint any tokens at the old rate.
        //
        _mintAccumulatedTokens(_account);

        addressToStreamInfo[_account].timeLastMinted = uint128(block.timestamp);
        addressToStreamInfo[_account].boost = _boost;

        emit CorruptionStreamBoostModified(_account, _boost);
    }

    function _beforeTokenTransfer(address _from, address _to, uint256 _amount) internal override whenNotPaused {
        _mintAccumulatedTokens(_from);
        _mintAccumulatedTokens(_to);

        super._beforeTokenTransfer(_from, _to, _amount);
    }

    function balanceOf(address _account) public view override(ERC20Upgradeable, IERC20Upgradeable) returns(uint256) {
        uint256 _tokenBalance = super.balanceOf(_account);
        (uint256 _accumulated,) = _tokensAccumulated(_account);
        return _tokenBalance + _accumulated;
    }

    function balanceOfBatch(address[] calldata _accounts) external view returns(uint256[] memory) {
        uint256[] memory _balances = new uint256[](_accounts.length);
        for(uint256 i = 0; i < _accounts.length; i++) {
            _balances[i] = balanceOf(_accounts[i]);
        }
        return _balances;
    }

    function mint(address _account, uint256 _amount) external onlyAdminOrOwner {
        _mint(_account, _amount);
    }

    function burn(address _account, uint256 _amount) external onlyAdminOrOwner {
        _burn(_account, _amount);
    }

    // Returns the number of tokens accumulated for the address as well as if this account
    // has a corruption stream active.
    //
    function _tokensAccumulated(address _account) private view returns(uint256, bool) {
        uint256 _tokenBalance = super.balanceOf(_account);

        CorruptionStreamInfo storage _streamInfo = addressToStreamInfo[_account];
        bool _hasStream = _streamInfo.ratePerSecond > 0;

        if(_tokenBalance >= _streamInfo.generatedCorruptionCap) {
            return (0, _hasStream);
        }

        uint256 _rawAccumulated = (block.timestamp - _streamInfo.timeLastMinted) * (_streamInfo.ratePerSecond * (100000 + _streamInfo.boost) / 100000);

        if(_tokenBalance + _rawAccumulated > _streamInfo.generatedCorruptionCap) {
            return (_streamInfo.generatedCorruptionCap - _tokenBalance, _hasStream);
        } else {
            return (_rawAccumulated, _hasStream);
        }
    }

    function _mintAccumulatedTokens(address _account) private {
        (uint256 _amount, bool _hasStream) = _tokensAccumulated(_account);

        if(_hasStream) {
            addressToStreamInfo[_account].timeLastMinted = uint128(block.timestamp);
        }
        if(_amount > 0) {
            _mint(_account, _amount);
        }
    }
}
