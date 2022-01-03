from scripts.helper import get_account, LOCAL_BLOCKCHAIN_ENVIRONMENTS
from brownie import network, DojoRouter, DojoBar, DojoHouse
import pytest
import time
from web3 import Web3

LINK = "0x01BE23585060835E02B77ef475b0Cc51aA1e0709"
AMOUNT = Web3.toWei(145, "ether")


def swap_tokens():
    account = get_account
    dojo_router = DojoRouter[-1]
    dojo_router.swapTokensforETH(1, LINK, AMOUNT, 100, {"from": account})


def main():
    swap_tokens()
