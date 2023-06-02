import { useCallback, useMemo } from 'react';
import { sprintf } from 'sprintf-js';
import styled from 'styled-components';

import { messages, relayLocations } from '../../shared/gettext';
import log from '../../shared/logging';
import { useAppContext } from '../context';
import { transitions, useHistory } from '../lib/history';
import { RoutePath } from '../lib/routes';
import { IRelayLocationRedux, RelaySettingsRedux } from '../redux/settings/reducers';
import { useSelector } from '../redux/store';
import { calculateHeaderBarStyle, DefaultHeaderBar } from './HeaderBar';
import ImageView from './ImageView';
import { Container, Layout } from './Layout';
import Map from './Map';
import NotificationArea from './NotificationArea';
import TunnelControl from './TunnelControl';

type MarkerOrSpinner = 'marker' | 'spinner' | 'none';

const StyledContainer = styled(Container)({
  position: 'relative',
});

const Content = styled.div({
  display: 'flex',
  flex: 1,
  flexDirection: 'column',
  position: 'relative', // need this for z-index to work to cover the map
  zIndex: 1,
});

const StatusIcon = styled(ImageView)({
  position: 'absolute',
  alignSelf: 'center',
  marginTop: 94,
});

const StyledNotificationArea = styled(NotificationArea)({
  position: 'absolute',
  left: 0,
  top: 0,
  right: 0,
});

const StyledMain = styled.main({
  display: 'flex',
  flexDirection: 'column',
  flex: 1,
});

export default function Connect() {
  const history = useHistory();
  const { connectTunnel, disconnectTunnel, reconnectTunnel } = useAppContext();

  const connection = useSelector((state) => state.connection);
  const blockWhenDisconnected = useSelector((state) => state.settings.blockWhenDisconnected);
  const relaySettings = useSelector((state) => state.settings.relaySettings);
  const relayLocations = useSelector((state) => state.settings.relayLocations);

  const showMarkerOrSpinner = useMemo<MarkerOrSpinner>(() => {
    if (!connection.latitude) {
      return 'none';
    }

    switch (connection.status.state) {
      case 'error':
        return 'none';
      case 'connecting':
      case 'disconnecting':
        return 'spinner';
      case 'connected':
      case 'disconnected':
        return 'marker';
    }
  }, [connection.latitude, connection.status.state]);

  const onSelectLocation = useCallback(() => {
    history.push(RoutePath.selectLocation, { transition: transitions.show });
  }, [history.push]);

  const selectedRelayName = useMemo(() => getRelayName(relaySettings, relayLocations), [
    relaySettings,
    relayLocations,
  ]);

  const onConnect = useCallback(async () => {
    try {
      await connectTunnel();
    } catch (e) {
      const error = e as Error;
      log.error(`Failed to connect the tunnel: ${error.message}`);
    }
  }, []);

  const onDisconnect = useCallback(async () => {
    try {
      await disconnectTunnel();
    } catch (e) {
      const error = e as Error;
      log.error(`Failed to disconnect the tunnel: ${error.message}`);
    }
  }, []);

  const onReconnect = useCallback(async () => {
    try {
      await reconnectTunnel();
    } catch (e) {
      const error = e as Error;
      log.error(`Failed to reconnect the tunnel: ${error.message}`);
    }
  }, []);

  return (
    <Layout>
      <DefaultHeaderBar barStyle={calculateHeaderBarStyle(connection.status)} />
      <StyledContainer>
        <Map />
        <Content>
          <StyledNotificationArea />

          <StyledMain>
            {/* show spinner when connecting */}
            {showMarkerOrSpinner === 'spinner' ? (
              <StatusIcon source="icon-spinner" height={60} width={60} />
            ) : null}

            <TunnelControl
              tunnelState={connection.status}
              blockWhenDisconnected={blockWhenDisconnected}
              selectedRelayName={selectedRelayName}
              city={connection.city}
              country={connection.country}
              onConnect={onConnect}
              onDisconnect={onDisconnect}
              onReconnect={onReconnect}
              onSelectLocation={onSelectLocation}
            />
          </StyledMain>
        </Content>
      </StyledContainer>
    </Layout>
  );
}

function getRelayName(relaySettings: RelaySettingsRedux, locations: IRelayLocationRedux[]): string {
  if ('normal' in relaySettings) {
    const location = relaySettings.normal.location;

    if (location === 'any') {
      return 'Automatic';
    } else if ('country' in location) {
      const country = locations.find(({ code }) => code === location.country);
      if (country) {
        return relayLocations.gettext(country.name);
      }
    } else if ('city' in location) {
      const [countryCode, cityCode] = location.city;
      const country = locations.find(({ code }) => code === countryCode);
      if (country) {
        const city = country.cities.find(({ code }) => code === cityCode);
        if (city) {
          return relayLocations.gettext(city.name);
        }
      }
    } else if ('hostname' in location) {
      const [countryCode, cityCode, hostname] = location.hostname;
      const country = locations.find(({ code }) => code === countryCode);
      if (country) {
        const city = country.cities.find(({ code }) => code === cityCode);
        if (city) {
          return sprintf(
            // TRANSLATORS: The selected location label displayed on the main view, when a user selected a specific host to connect to.
            // TRANSLATORS: Example: Malmö (se-mma-001)
            // TRANSLATORS: Available placeholders:
            // TRANSLATORS: %(city)s - a city name
            // TRANSLATORS: %(hostname)s - a hostname
            messages.pgettext('connect-container', '%(city)s (%(hostname)s)'),
            {
              city: relayLocations.gettext(city.name),
              hostname,
            },
          );
        }
      }
    }

    return 'Unknown';
  } else if (relaySettings.customTunnelEndpoint) {
    return 'Custom';
  } else {
    throw new Error('Unsupported relay settings.');
  }
}
