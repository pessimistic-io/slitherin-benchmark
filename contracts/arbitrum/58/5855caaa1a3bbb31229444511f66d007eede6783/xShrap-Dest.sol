/*     +%%#-                           ##.        =+.    .+#%#+:       *%%#:    .**+-      =+
 *   .%@@*#*:                          @@: *%-   #%*=  .*@@=.  =%.   .%@@*%*   +@@=+=%   .%##
 *  .%@@- -=+                         *@% :@@-  #@=#  -@@*     +@-  :@@@: ==* -%%. ***   #@=*
 *  %@@:  -.*  :.                    +@@-.#@#  =@%#.   :.     -@*  :@@@.  -:# .%. *@#   *@#*
 * *%@-   +++ +@#.-- .*%*. .#@@*@#  %@@%*#@@: .@@=-.         -%-   #%@:   +*-   =*@*   -@%=:
 * @@%   =##  +@@#-..%%:%.-@@=-@@+  ..   +@%  #@#*+@:      .*=     @@%   =#*   -*. +#. %@#+*@
 * @@#  +@*   #@#  +@@. -+@@+#*@% =#:    #@= :@@-.%#      -=.  :   @@# .*@*  =@=  :*@:=@@-:@+
 * -#%+@#-  :@#@@+%++@*@*:=%+..%%#=      *@  *@++##.    =%@%@%%#-  =#%+@#-   :*+**+=: %%++%*
 *
 * @title: LZ ERC-20 wrapper for xShrap v2, written in UUPS (ERC-1822/1967)
 * @author Max Flow O2 -> @MaxFlowO2 on bird app/GitHub
 */

// SPDX-License-Identifier: Apache-2.0

/******************************************************************************
 * Copyright 2023 Max Flow O2                                                 *
 *                                                                            *
 * Licensed under the Apache License, Version 2.0 (the "License");            *
 * you may not use this file except in compliance with the License.           *
 * You may obtain a copy of the License at                                    *
 *                                                                            *
 *     http://www.apache.org/licenses/LICENSE-2.0                             *
 *                                                                            *
 * Unless required by applicable law or agreed to in writing, software        *
 * distributed under the License is distributed on an "AS IS" BASIS,          *
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.   *
 * See the License for the specific language governing permissions and        *
 * limitations under the License.                                             *
 ******************************************************************************/

pragma solidity >=0.8.0 <0.9.0;

import "./Max-20-UUPS-LZ.sol";
import "./Safe20.sol";
import "./20.sol";
import "./Lists.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";

contract xShrapDest is Initializable
                     , Max20ImplementationUUPSLZ
                     , UUPSUpgradeable {

  using Lib20 for Lib20.Token;
  using Lists for Lists.Access;
  using Safe20 for IERC20;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  /// @dev pay attention to this bad boy
  /// @param _name string of wrapped token's full _name
  /// @param _symbol "ticker" of wrapped token
  /// @param _admin address authorized for proxy upgrades
  /// @param _dev address for onlyDev() exclusions
  /// @param _owner address for EIP 173 compliance (kinda backwards for xxxscan stuff)
  /// @notice set your own decimals or add that if you wish to deployer script
  function initialize(
    string memory _name
  , string memory _symbol
  , address _admin
  , address _dev
  , address _owner
  ) initializer
    public {
      __Max20_init(_name, _symbol, 18,  _admin, _dev, _owner);
      __UUPSUpgradeable_init();
  }

  function _authorizeUpgrade(address newImplementation)
    internal
    onlyRole(ADMIN)
    override
    {}

  function addExempt(
    address newAddress
  ) external
    virtual
    onlyDev() {
    taxExempt.add(newAddress);
  }

  function removeExempt(
    address newAddress
  ) external
    virtual
    onlyDev() {
    taxExempt.remove(newAddress);
  }

  function addExemptBatch(
    address[] memory newAddresses
  ) external
    virtual
    onlyDev() {
    uint len = newAddresses.length;
    for (uint i = 0; i < len;) {
      taxExempt.add(newAddresses[i]);
      unchecked { ++i; }
    }
  }

  function removeExemptBatch(
    address[] memory newAddresses
  ) external
    virtual
    onlyDev() {
    uint len = newAddresses.length;
    for (uint i = 0; i < len;) {
      taxExempt.remove(newAddresses[i]);
      unchecked { ++i; }
    }
  }

  /// @dev sets taxes
  /// @param _newTTax, Transfer Tax (Treasury)
  /// @param _newBTax, Bridge Tax (Treasury)
  /// @param _newTBurn, Transfer Burn
  /// @param _newBBurn, Bridge Burn
  /// @notice use BPS since everything is / 10000
  function setTaxes(
    uint16 _newTTax
  , uint16 _newBTax
  , uint16 _newTBurn
  , uint16 _newBBurn
  ) external
    virtual
    onlyDev() {
    BPSTTax = _newTTax;
    BPSBTax = _newBTax;
    BPSTBurn = _newTBurn;
    BPSBBurn = _newBBurn;
  }

  /// @dev sets the treasury address
  /// @param newAddress, 0x address (EOA/Multisig)
  function setTres(
    address newAddress
  ) external
    virtual
    onlyDev() {
    Treasury = newAddress;
  }

  /// @dev transfer
  /// @return success
  /// @notice Transfers _value amount of tokens to address _to, and MUST fire the Transfer event.
  ///         The function SHOULD throw if the message caller’s account balance does not have enough
  ///         tokens to spend.
  /// @notice Note Transfers of 0 values MUST be treated as normal transfers and fire the Transfer
  ///         event.
  function transfer(
    address _to
  , uint256 _value
  ) external
    virtual
    override
    returns (bool success) {
    uint256 balanceUser = this.balanceOf(msg.sender);
    if (_to == address(0)) {
      revert MaxSplaining({
        reason: "Max20: to address(0)"
      });
    } else if (_value > balanceUser) {
      revert MaxSplaining({
        reason: "Max20: insufficient balance"
      });
    } else {
      if (taxExempt.onList(_to) || taxExempt.onList(msg.sender)) {
        // untaxed
        token20.doTransfer(msg.sender, _to, _value);
        emit Transfer(msg.sender, _to, _value);
        return true;
      } else {
        // First BPS on deposit...
        uint256 taxed = 10000 - BPSTTax - BPSTBurn;
        uint256 toTrans = taxed * _value / 10000;
        uint256 toTreas = BPSTTax * _value / 10000;
        // mint and emit event
        token20.doTransfer(msg.sender, _to, toTrans);
        token20.doTransfer(msg.sender, Treasury, toTreas);
        token20.burn(msg.sender, _value - toTrans - toTreas);
        emit Transfer(msg.sender, _to, toTrans);
        emit Transfer(msg.sender, Treasury, toTreas);
        emit Transfer(msg.sender, address(0), _value - toTrans - toTreas);
        return true;
      }
    }
  }

  /// @dev transferFrom
  /// @return success
  /// @notice The transferFrom method is used for a withdraw workflow, allowing contracts to transfer
  ///         tokens on your behalf. This can be used for example to allow a contract to transfer
  ///         tokens on your behalf and/or to charge fees in sub-currencies. The function SHOULD
  ///         throw unless the _from account has deliberately authorized the sender of the message
  ///         via some mechanism.
  /// @notice Note Transfers of 0 values MUST be treated as normal transfers and fire the Transfer
  ///         event.
  function transferFrom(
    address _from
  , address _to
  , uint256 _value
  ) external
    virtual
    override
    returns (bool success) {
    uint256 balanceUser = this.balanceOf(_from);
    uint256 approveBal = this.allowance(_from, msg.sender);
    if (_from == address(0) || _to == address(0)) {
      revert MaxSplaining({
        reason: "Max20: to/from address(0)"
      });
    } else if (_value > balanceUser) {
      revert MaxSplaining({
        reason: "Max20: insufficient balance"
      });
    } else if (_value > approveBal) {
      revert MaxSplaining({
        reason: "Max20: not approved to spend _value"
      });
    } else {
      if (taxExempt.onList(_to) || taxExempt.onList(_from)) {
        // untaxed
        token20.doTransfer(_from, _to, _value);
        emit Transfer(_from, _to, _value);
        token20.setApprove(_from, msg.sender, approveBal - _value);
        emit Approval(_from, msg.sender, approveBal - _value);
        return true;
      } else {
        // First BPS on deposit...
        uint256 taxed = 10000 - BPSTTax - BPSTBurn;
        uint256 toTrans = taxed * _value / 10000;
        uint256 toTreas = BPSTTax * _value / 10000;
        // mint and emit event
        token20.doTransfer(_from, _to, toTrans);
        token20.doTransfer(_from, Treasury, toTreas);
        token20.burn(_from, _value - toTrans - toTreas);
        emit Transfer(_from, _to, toTrans);
        emit Transfer(_from, Treasury, toTreas);
        emit Transfer(_from, address(0), _value - toTrans - toTreas);
        token20.setApprove(_from, msg.sender, approveBal - _value);
        emit Approval(_from, msg.sender, approveBal - _value);
        return true;
      }
    }
  }

  /// @dev burn
  /// @return success
  /// @notice Burns _value amount of tokens to address _to, and MUST fire the Transfer event.
  ///         The function SHOULD throw if the message caller’s account balance does not have enough
  ///         tokens to burn.
  /// @notice Note burn of 0 values MUST be treated as normal transfers and fire the Transfer
  ///         event.
  function burn(
    uint256 _value
  ) external
    virtual
    returns (bool success) {
    uint256 balanceUser = this.balanceOf(msg.sender);
    if (_value > balanceUser) {
      revert MaxSplaining({
        reason: "Max20: insufficient balance"
      });
    } else {
      token20.burn(msg.sender, _value);
      success = true;
      emit Transfer(msg.sender, address(0), _value);
    }
  }

  /// @notice This function transfers the ft from your address on the
  ///          source chain to the same address on the destination chain
  /// @param _chainId: the uint16 of desination chain (see LZ docs)
  /// @param _amount: amount to be sent
  function traverseChains(
    uint16 _chainId
  , uint256 _amount
  ) public
    virtual
    payable {
    uint256 userBal = token20.getBalanceOf(msg.sender);
    if (_amount > userBal) {
      revert Unauthorized();
    }
    if (trustedRemoteLookup[_chainId].length == 0) {
      revert MaxSplaining({
        reason: "Token: TR not set"
      });
    }

    uint256 toTraverse = 0;
    // burn FT, eliminating it from circulation on src chain
    if (!taxExempt.onList(msg.sender)) {
      // First BPS on deposit...
      uint256 taxed = 10000 - BPSBTax - BPSBBurn;
      toTraverse = taxed * _amount / 10000;
      uint256 toTreas = BPSBTax * _amount / 10000;
      // burn and emit event
      token20.burn(msg.sender, _amount - toTreas);
      token20.doTransfer(msg.sender, Treasury, toTreas);
      emit Transfer(msg.sender, Treasury, toTreas);
      emit Transfer(msg.sender, address(0), _amount - toTreas);
    } else {
      // untaxed
      toTraverse = _amount;
      token20.burn(msg.sender, _amount);
      emit Transfer(address(0), msg.sender, _amount);
    }

    // abi.encode() the payload with the values to send
    bytes memory payload = abi.encode(
                             msg.sender
                           , toTraverse);

    // encode adapterParams to specify more gas for the destination
    uint16 version = 1;
    bytes memory adapterParams = abi.encodePacked(
                                   version
                                 , gasForDestinationLzReceive);

    // get the fees we need to pay to LayerZero + Relayer to cover message delivery
    // you will be refunded for extra gas paid
    (uint messageFee, ) = endpoint.estimateFees(
                            _chainId
                          , address(this)
                          , payload
                          , false
                          , adapterParams);

    // revert this transaction if the fees are not met
    if (messageFee > msg.value) {
      revert MaxSplaining({
        reason: "Token: message fee low"
      });
    }

    // send the transaction to the endpoint
    endpoint.send{value: msg.value}(
      _chainId,                           // destination chainId
      trustedRemoteLookup[_chainId],      // destination address of nft contract
      payload,                            // abi.encoded()'ed bytes
      payable(msg.sender),                // refund address
      address(0x0),                       // 'zroPaymentAddress' unused for this
      adapterParams                       // txParameters
    );
  }

  // @notice just in case this fixed variable limits us from future integrations
  // @param newVal: new value for gas amount
  function setGasForDestinationLzReceive(
    uint newVal
  ) external onlyDev() {
    gasForDestinationLzReceive = newVal;
  }

  /// @notice internal function to mint FT from migration
  /// @param _srcChainId - the source endpoint identifier
  /// @param _srcAddress - the source sending contract address from the source chain
  /// @param _nonce - the ordered message nonce
  /// @param _payload - the signed payload is the UA bytes has encoded to be sent
  function _LzReceive(
    uint16 _srcChainId
  , bytes memory _srcAddress
  , uint64 _nonce
  , bytes memory _payload
  ) override
    internal {
    // decode
    (address toAddr, uint256 amount) = abi.decode(_payload, (address, uint256));

    // mint the tokens back into existence on destination chain
    token20.mint(toAddr, amount);
    emit Transfer(address(0), toAddr, amount);
  }

  // @notice will return gas value for LZ
  // @return: uint for gas value
  function currentLZGas()
    external
    view
    returns (uint256) {
    return gasForDestinationLzReceive;
  }  
}

