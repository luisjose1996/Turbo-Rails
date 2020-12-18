# Turbo streams can be broadcast directly from models that include this module (this is automatically done for Active Records).
# This makes it convenient to execute both synchronous and asynchronous updates, and render directly from callbacks in models
# or from controllers or jobs that act on those models. Here's an example:
#
#   class Clearance < ApplicationRecord
#     belongs_to :petitioner, class_name: "Contact"
#     belongs_to :examiner,   class_name: "User"
#
#     after_create_commit :broadcast_later
#
#     private
#       def broadcast_later
#         broadcast_prepend_later_to examiner.identity, :clearances
#       end
#   end
#
# This is an example from [HEY](https://hey.com), and the clearance is the model that drives
# [the screener](https://hey.com/features/the-screener/), which gives users the power to deny first-time senders (petitioners)
# access to their attention (as the examiner). When a new clearance is created upon receipt of an email from a first-time
# sender, that'll trigger the call to broadcast_later, which in turn invokes <tt>broadcast_prepend_later_to</tt>.
#
# That method enqueues a <tt>Turbo::Streams::ActionBroadcastJob</tt> for the prepend, which will render the partial for clearance
# (it knows which by calling Clearance#to_partial_path, which in this case returns <tt>clearances/_clearance.html.erb</tt>),
# send that to all users that have subscribed to updates (using <tt>turbo_stream_from(examiner.identity, :clearances)</tt> in a view)
# using the <tt>Turbo::StreamsChannel</tt> under the stream name derived from <tt>[ examiner.identity, :clearances ]</tt>,
# and finally prepend the result of that partial rendering to the container identified with the dom id "clearances"
# (which is derived by default from the plural model name of the model, but can be overwritten).
#
# There are four basic actions you can broadcast: <tt>remove</tt>, <tt>replace</tt>, <tt>append</tt>, and
# <tt>prepend</tt>. As a rule, you should use the <tt>_later</tt> versions of everything except for remove when broadcasting
# within a real-time path, like a controller or model, since all those updates require a rendering step, which can slow down
# execution. You don't need to do this for remove, since only the dom id for the model is used.
#
# In addition to the four basic actions, you can also use <tt>broadcast_render_later</tt> or
# <tt>broadcast_render_later_to</tt> to render a turbo stream template with multiple actions.
module Turbo::Broadcastable
  extend ActiveSupport::Concern

  module ClassMethods
    # Configures the model to broadcast creates, updates, and destroys to a stream name derived at runtime by the
    # <tt>stream</tt> symbol invocation. By default, the creates are appended to a dom id container name derived from
    # the model's plural name. The insertion can also be made to be a prepend by overwriting <tt>insertion</tt> and
    # the container dom id overwritten by passing <tt>container</tt>. Examples:
    #
    #   class Message < ApplicationRecord
    #     belongs_to :board
    #     broadcasts_to :board
    #   end
    #
    #   class Message < ApplicationRecord
    #     belongs_to :board
    #     broadcasts_to ->(message) { [ message.board, :messages ] }, inserts_by: :prepend, container: "board_messages"
    #   end
    def broadcasts_to(stream, inserts_by: :append, container: model_name.plural)
      after_create_commit  -> { broadcast_action_later_to stream.try(:call, self) || send(stream), action: inserts_by, container: container }
      after_update_commit  -> { broadcast_replace_later_to stream.try(:call, self) || send(stream) }
      after_destroy_commit -> { broadcast_remove_to stream.try(:call, self) || send(stream) }
    end

    # Same as <tt>#broadcasts_to</tt>, but the designated stream is automatically set to the current model.
    def broadcasts(inserts_by: :append, container: model_name.plural)
      broadcasts_to self, inserts_by: inserts_by, container: container
    end
  end

  # Remove this broadcastable model from the dom for subscribers of the stream name identified by the passed streamables.
  # Example:
  #
  #   # Sends <turbo-stream action="remove" target="clearance_5"></turbo-stream> to the stream named "identity:2:clearances"
  #   clearance.broadcast_remove_to examiner.identity, :clearances
  def broadcast_remove_to(*streamables)
    Turbo::StreamsChannel.broadcast_remove_to *streamables, element: self
  end

  # Same as <tt>#broadcast_remove_to</tt>, but the designated stream is automatically set to the current model.
  def broadcast_remove
    broadcast_remove_to self
  end

  # Replace this broadcastable model in the dom for subscribers of the stream name identified by the passed
  # <tt>streamables</tt>. The rendering parameters can be set by appending named arguments to the call. Examples:
  #
  #   # Sends <turbo-stream action="replace" target="clearance_5"><template><div id="clearance_5">My Clearance</div></template></turbo-stream>
  #   # to the stream named "identity:2:clearances"
  #   clearance.broadcast_replace_to examiner.identity, :clearances
  #
  #   # Sends <turbo-stream action="replace" target="clearance_5"><template><div id="clearance_5">Other partial</div></template></turbo-stream>
  #   # to the stream named "identity:2:clearances"
  #   clearance.broadcast_replace_to examiner.identity, :clearances, partial: "clearances/other_partial", locals: { a: 1 }
  def broadcast_replace_to(*streamables, **rendering)
    Turbo::StreamsChannel.broadcast_replace_to *streamables, element: self, **broadcast_rendering_with_defaults(rendering)
  end

  # Same as <tt>#broadcast_replace_to</tt>, but the designated stream is automatically set to the current model.
  def broadcast_replace(**rendering)
    broadcast_replace_to self, **rendering
  end

  # Append a rendering of this broadcastable model to the container identified by it's dom id passed as <tt>container</tt>
  # for subscribers of the stream name identified by the passed <tt>streamables</tt>. The rendering parameters can be set by
  # appending named arguments to the call. Examples:
  #
  #   # Sends <turbo-stream action="append" target="clearances"><template><div id="clearance_5">My Clearance</div></template></turbo-stream>
  #   # to the stream named "identity:2:clearances"
  #   clearance.broadcast_append_to examiner.identity, :clearances, container: "clearances"
  #
  #   # Sends <turbo-stream action="append" target="clearances"><template><div id="clearance_5">Other partial</div></template></turbo-stream>
  #   # to the stream named "identity:2:clearances"
  #   clearance.broadcast_append_to examiner.identity, :clearances, container: "clearances",
  #     partial: "clearances/other_partial", locals: { a: 1 }
  def broadcast_append_to(*streamables, container: broadcast_container_default, **rendering)
    Turbo::StreamsChannel.broadcast_append_to *streamables, container: container, **broadcast_rendering_with_defaults(rendering)
  end

  # Same as <tt>#broadcast_append_to</tt>, but the designated stream is automatically set to the current model.
  def broadcast_append(container: broadcast_container_default, **rendering)
    broadcast_append_to self, container: container, **rendering
  end

  # Prepend a rendering of this broadcastable model to the container identified by it's dom id passed as <tt>container</tt>
  # for subscribers of the stream name identified by the passed <tt>streamables</tt>. The rendering parameters can be set by
  # appending named arguments to the call. Examples:
  #
  #   # Sends <turbo-stream action="prepend" target="clearances"><template><div id="clearance_5">My Clearance</div></template></turbo-stream>
  #   # to the stream named "identity:2:clearances"
  #   clearance.broadcast_prepend_to examiner.identity, :clearances, container: "clearances"
  #
  #   # Sends <turbo-stream action="prepend" target="clearances"><template><div id="clearance_5">Other partial</div></template></turbo-stream>
  #   # to the stream named "identity:2:clearances"
  #   clearance.broadcast_prepend_to examiner.identity, :clearances, container: "clearances",
  #     partial: "clearances/other_partial", locals: { a: 1 }
  def broadcast_prepend_to(*streamables, container: broadcast_container_default, **rendering)
    Turbo::StreamsChannel.broadcast_prepend_to *streamables, container: container, **broadcast_rendering_with_defaults(rendering)
  end

  # Same as <tt>#broadcast_append_to</tt>, but the designated stream is automatically set to the current model.
  def broadcast_prepend(container: broadcast_container_default, **rendering)
    broadcast_prepend_to self, container: container, **rendering
  end

  # Broadcast a named <tt>action</tt>, allowing for dynamic dispatch, instead of using the concrete action methods. Examples:
  #
  #   # Sends <turbo-stream action="prepend" target="clearances"><template><div id="clearance_5">My Clearance</div></template></turbo-stream>
  #   # to the stream named "identity:2:clearances"
  #   clearance.broadcast_action_to examiner.identity, :clearances, action: :prepend, container: "clearances"
  def broadcast_action_to(*streamables, action:, dom_id: broadcast_container_default, **rendering)
    Turbo::StreamsChannel.broadcast_action_to(*streamables, action: action, dom_id: dom_id, **broadcast_rendering_with_defaults(rendering))
  end

  # Same as <tt>#broadcast_action_to</tt>, but the designated stream is automatically set to the current model.
  def broadcast_action(action:, dom_id: broadcast_container_default, **rendering)
    broadcast_action_to self, action: action, dom_id: dom_id, **rendering
  end


  # Same as <tt>broadcast_replace_to</tt> but run asynchronously via a <tt>Turbo::Streams::BroadcastJob</tt>.
  def broadcast_replace_later_to(*streamables, **rendering)
    Turbo::StreamsChannel.broadcast_replace_later_to *streamables, element: self, **broadcast_rendering_with_defaults(rendering)
  end

  # Same as <tt>#broadcast_replace_later_to</tt>, but the designated stream is automatically set to the current model.
  def broadcast_replace_later(**rendering)
    broadcast_replace_later_to self, **rendering
  end

  # Same as <tt>broadcast_append_to</tt> but run asynchronously via a <tt>Turbo::Streams::BroadcastJob</tt>.
  def broadcast_append_later_to(*streamables, container: broadcast_container_default, **rendering)
    Turbo::StreamsChannel.broadcast_append_later_to *streamables, container: container, **broadcast_rendering_with_defaults(rendering)
  end

  # Same as <tt>#broadcast_append_later_to</tt>, but the designated stream is automatically set to the current model.
  def broadcast_append_later(container: broadcast_container_default, **rendering)
    broadcast_append_later_to self, container: container, **rendering
  end

  # Same as <tt>broadcast_prepend_to</tt> but run asynchronously via a <tt>Turbo::Streams::BroadcastJob</tt>.
  def broadcast_prepend_later_to(*streamables, container: broadcast_container_default, **rendering)
    Turbo::StreamsChannel.broadcast_prepend_later_to *streamables, container: container, **broadcast_rendering_with_defaults(rendering)
  end

  # Same as <tt>#broadcast_prepend_later_to</tt>, but the designated stream is automatically set to the current model.
  def broadcast_prepend_later(container: broadcast_container_default, **rendering)
    broadcast_prepend_later_to self, container: container, **rendering
  end

  # Same as <tt>broadcast_action_later_to</tt> but run asynchronously via a <tt>Turbo::Streams::BroadcastJob</tt>.
  def broadcast_action_later_to(*streamables, action:, dom_id: broadcast_container_default, **rendering)
    Turbo::StreamsChannel.broadcast_action_later_to(*streamables, action: action, dom_id: dom_id, **broadcast_rendering_with_defaults(rendering))
  end

  # Same as <tt>#broadcast_action_later_to</tt>, but the designated stream is automatically set to the current model.
  def broadcast_action_later(action:, dom_id: broadcast_container_default, **rendering)
    broadcast_action_later_to self, action: action, dom_id: dom_id, **rendering
  end


  # Render a turbo stream template asynchronously with this broadcastable model passed as the local variable using a
  # <tt>Turbo::Streams::BroadcastJob</tt>. Example:
  #
  #   # Template: entries/_entry.turbo_stream.erb
  #   <%= turbo_stream.remove entry %>
  #
  #   <%= turbo_stream.append "entries" do %>
  #     <%= render partial: "entries/entry", locals: { entry: entry }, formats: [ :html ] %>
  #   <% end if entry.active? %>
  #
  #   # Sends:
  #   #   <turbo-stream action="remove" target="entry_5"></turbo-stream>
  #   #   <turbo-stream action="append" target="entries"><template><div id="entry_5">My Entry</div></template></turbo-stream>
  #   # to the stream named "entry:5"
  #   entry.broadcast_render_later
  def broadcast_render_later(**rendering)
    broadcast_render_later_to self, **rendering
  end

  # Same as <tt>broadcast_prepend_to</tt> but run with the added option of naming the stream using the passed
  # <tt>streamables</tt>.
  def broadcast_render_later_to(*streamables, **rendering)
    Turbo::StreamsChannel.broadcast_render_later_to *streamables, **broadcast_rendering_with_defaults(rendering)
  end


  private
    def broadcast_container_default
      model_name.plural
    end

    def broadcast_rendering_with_defaults(options)
      options.tap do |o|
        o[:locals]    = (o[:locals] || {}).reverse_merge!(model_name.singular.to_sym => self)
        o[:partial] ||= to_partial_path
      end
    end
end
