# Run by `railway-zammad zammad-init` (pre-deploy) after Zammad's own init,
# with `bundle exec rails r`.
#
# 1. Stores the Elasticsearch settings (upstream init does this too, but also
#    blocks until Elasticsearch answers; the index is built by zammad-scheduler).
# 2. First install only: creates the administrator from ZAMMAD_ADMIN_* and marks
#    the system as initialised, so nobody who finds the URL first can claim the
#    instance through the getting-started wizard.

def env(name)
  ENV[name].to_s.strip.presence
end

if ENV['ELASTICSEARCH_ENABLED'].to_s != 'false' && env('ELASTICSEARCH_HOST')
  schema = env('ELASTICSEARCH_SCHEMA') || 'http'
  port = env('ELASTICSEARCH_PORT') || '9200'
  Setting.set('es_url', "#{schema}://#{env('ELASTICSEARCH_HOST')}:#{port}")
  Setting.set('es_index', env('ELASTICSEARCH_NAMESPACE') || 'zammad')
  if env('ELASTICSEARCH_USER') && env('ELASTICSEARCH_PASS')
    Setting.set('es_user', env('ELASTICSEARCH_USER'))
    Setting.set('es_password', env('ELASTICSEARCH_PASS'))
  end
  puts '[railway-zammad] Elasticsearch settings stored'
end

if Setting.get('system_init_done')
  puts '[railway-zammad] system already initialised; admin bootstrap skipped'
elsif env('ZAMMAD_ADMIN_EMAIL') && env('ZAMMAD_ADMIN_PASSWORD')
  # Same service the setup wizard calls for its first administrator (roles
  # Admin + Agent, access to all groups, system_init_done, calendar and text
  # modules), without an HTTP request.
  request = Struct.new(:remote_ip, :env).new(nil, { 'HTTP_ACCEPT_LANGUAGE' => 'en-us' })
  admin = Service::User::AddFirstAdmin.new(
    user_data: {
      firstname: env('ZAMMAD_ADMIN_FIRSTNAME') || 'Admin',
      lastname:  env('ZAMMAD_ADMIN_LASTNAME') || 'User',
      email:     env('ZAMMAD_ADMIN_EMAIL').downcase,
      password:  env('ZAMMAD_ADMIN_PASSWORD'),
    },
    request:   request,
  ).execute

  UserInfo.ensure_current_user_id do
    Setting.set('organization', env('ZAMMAD_ORGANIZATION')) if env('ZAMMAD_ORGANIZATION')
    Setting.set('product_name', env('ZAMMAD_PRODUCT_NAME')) if env('ZAMMAD_PRODUCT_NAME')
  end
  puts "[railway-zammad] administrator #{admin.email} created; setup wizard closed"
else
  puts '[railway-zammad] WARNING: ZAMMAD_ADMIN_EMAIL/ZAMMAD_ADMIN_PASSWORD not set; ' \
       'the first visitor can claim this instance through the setup wizard'
end
