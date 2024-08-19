// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./BaseRelayRecipient.sol";

contract Whitelist is Ownable, BaseRelayRecipient {
    mapping(address => mapping(address => bool)) private _whitelist;
    error AddressZero();

    constructor(
        address owner_,
        address trustedForwarder_
    ) 
    Ownable(owner_) 
    BaseRelayRecipient(trustedForwarder_)
    {}

    modifier nonZeroAddress(address anAddress) {
        if (anAddress == address(0)) revert AddressZero();
        _;
    }
    
    function _msgSender() internal override(Context, BaseRelayRecipient) view returns(address){
        return BaseRelayRecipient._msgSender();
    }

    function exists(
        address anUser,
        address aToken
    ) external view returns (bool) {
        return _whitelist[aToken][anUser];
    }

    function add(
        address anUser,
        address aToken
    ) external onlyOwner nonZeroAddress(anUser) nonZeroAddress(aToken) {
        _whitelist[aToken][anUser] = true;
    }

    function remove(
        address anUser,
        address aToken
    ) external onlyOwner nonZeroAddress(anUser) nonZeroAddress(aToken) {
        _whitelist[aToken][anUser] = false;
    }
}
