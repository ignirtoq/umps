from asyncio import CancelledError, Task, get_event_loop
from collections import defaultdict
from ipaddress import IPv4Network
from itertools import islice
from logging import getLogger
from typing import Callable

from .exceptions import NotConnectedError, NotSubscribedError
from .hash import hash_v1
from .publish import PublishProtocol, create_publish_socket
from .subscribe import SubscribeProtocol, create_subscribe_socket


def _nth(it, n):
    return next(islice(it, n, None))


class Interface:

    def __init__(self, network: IPv4Network, port: int,
                 protocol_version=1, loop=None):
        if protocol_version != 1:
            raise NotImplementedError("protocol versions other than 1 not "
                                      "supported")

        self._loop = get_event_loop() if loop is None else loop
        self._log = getLogger(__name__)
        self._net = network
        self._port = port
        self._nbins = self._calculate_nbins()
        self._startup_tasks = set()
        self._subscriptions = defaultdict(set)
        self._topic_callbacks = defaultdict(list)
        # setup the publish protocol
        self._publish_protocol: PublishProtocol = None
        self._startup_tasks.add(
            self._loop.create_task(self._setup_publish_protocol()))
        # setup the subscribe protocol
        self._subscribe_protocol: SubscribeProtocol = None
        self._startup_tasks.add(
            self._loop.create_task(self._setup_subscribe_protocol()))

        self._hash = hash_v1

    async def terminate(self):
        if self._startup_tasks:
            tasks = self._startup_tasks.copy()
            for task in tasks:
                task.cancel()
                await task
        if self._publish_protocol is not None:
            self._publish_protocol.close()
        if self._subscribe_protocol is not None:
            self._subscribe_protocol.close()

    async def subscribe(self, topic: str,
                        callback: Callable[[str, bytes], None]):
        if self._startup_tasks:
            tasks = self._startup_tasks.copy()
            for task in tasks:
                await task

        if self._subscribe_protocol is None:
            raise NotConnectedError

        self._add_subscription(topic, callback)

    async def unsubscribe(self, topic: str):
        if self._startup_tasks:
            tasks = self._startup_tasks.copy()
            for task in tasks:
                await task

        if self._subscribe_protocol is None:
            raise NotConnectedError

        self._remove_subscription(topic)

    async def publish(self, topic: str, message: bytes):
        if self._startup_tasks:
            tasks = self._startup_tasks.copy()
            for task in tasks:
                await task

        if self._publish_protocol is None:
            raise NotConnectedError

        address_bin = self._hash(topic, self._nbins)
        address = self._get_address_of_bin(address_bin)
        self._publish_protocol.publish((address, self._port), topic, message)

    def _add_subscription(self, topic: str,
                          callback: Callable[[str, bytes], None]):
        address_bin = self._hash(topic, self._nbins)
        address = self._get_address_of_bin(address_bin)

        if address not in self._subscriptions:
            self._subscribe_protocol.subscribe(address)
        self._subscriptions[address].add(topic)
        self._topic_callbacks[topic].append(callback)

    def _remove_subscription(self, topic: str):
        address_bin = self._hash(topic, self._nbins)
        address = self._get_address_of_bin(address_bin)

        if address not in self._subscriptions:
            raise NotSubscribedError
        if topic not in self._subscriptions[address]:
            raise NotSubscribedError

        self._subscriptions[address].remove(topic)
        self._topic_callbacks.pop(topic)
        if not self._subscriptions[address]:
            self._subscribe_protocol.unsubscribe(address)
            self._subscriptions.pop(address)

    def _calculate_nbins(self):
        # Remove network and broadcast addresses from count.
        return self._net.num_addresses - 2

    def _get_address_of_bin(self, address_bin):
        return str(_nth(self._net.hosts(), address_bin))

    def _message_callback(self, topic: str, message: bytes):
        if topic not in self._topic_callbacks:
            self._log.debug("received '%s' message with no callbacks", topic)
            return

        for callback in self._topic_callbacks[topic]:
            callback(topic, message)

    async def _setup_publish_protocol(self):
        local_address = ('0.0.0.0', 0)
        try:
            self._publish_protocol = await create_publish_socket(
                local_address, loop=self._loop)
        except CancelledError:
            pass

        self._startup_tasks.remove(Task.current_task(loop=self._loop))

    async def _setup_subscribe_protocol(self):
        local_address = ('0.0.0.0', self._port)
        try:
            self._subscribe_protocol = await create_subscribe_socket(
                local_address, loop=self._loop,
                message_callback=self._message_callback)
        except CancelledError:
            pass

        self._startup_tasks.remove(Task.current_task(loop=self._loop))
