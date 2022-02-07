from brownie import (
    accounts,
    network,
    config,
    Contract,
    LinkToken,
)
from web3 import Web3

LINK_AMOUNT = Web3.toWei(200, "ether")


def get_account(index=None, id=None):
    if index:
        return accounts[index]
    if id:
        return accounts.load(id)
    return accounts.add(config["wallets"]["key1"])


def get_account2():
    return accounts.add(config["wallets"]["key2"])


def fund_with_link(contract_address):
    account = get_account()
    link_token = get_contract("link_token")
    tx = link_token.transfer(contract_address, LINK_AMOUNT, {"from": account})
    tx.wait(1)
    print("Funded contract with Link")
    return tx


def get_contract(contract_name):
    contract_to_mock = {
        "link_token": LinkToken,
    }
    contract_type = contract_to_mock[contract_name]
    contract_address = config["networks"][network.show_active()][contract_name]
    # address
    # ABI
    contract = Contract.from_abi(
        contract_type._name, contract_address, contract_type.abi
    )
    # MockV3Aggregator.abi
    return contract
